# ── Service MatchEnrollmentService ────────────────────────────────────────────
# Encapsule TOUTE la logique métier d'inscription d'un joueur à un match, extraite
# de MatchUsersController#create afin de pouvoir la réutiliser depuis un autre
# point d'entrée (notamment l'inscription déclenchée depuis Slack — cf. PR 6).
#
# Responsabilités du service (métier pur, sans HTTP) :
#   - refus si déjà inscrit / si restriction de genre non respectée ;
#   - décision waiting / pending / approved selon l'état du match, avec le même
#     verrou `with_lock` (SELECT FOR UPDATE) que l'original pour éviter les races ;
#   - création de la notification in-app à l'organisateur + email transactionnel.
#
# Ce qui reste au controller (dépend du contexte web) : `authorize`, les
# broadcasts Turbo temps réel, le flash et les redirections. Le controller mappe
# simplement `result.status` vers la bonne réponse.
#
# Utilisation :
#   result = MatchEnrollmentService.new(match: @match, user: current_user,
#                                       message: params[:message].presence).call
#   result.status # => :approved | :waiting | :pending
#                 #    | :already_registered | :gender_restricted | :error
class MatchEnrollmentService
  # Les helpers de routes (match_path) ne sont pas disponibles par défaut hors
  # controller/vue → on les inclut pour construire le lien de la notification.
  include Rails.application.routes.url_helpers

  # Résultat de la tentative. `match_user` est l'inscription créée (nil pour les
  # refus en amont : déjà inscrit / genre).
  Result = Struct.new(:status, :match_user, keyword_init: true)

  def initialize(match:, user:, message: nil)
    @match   = match
    @user    = user
    @message = message
  end

  def call
    # Déjà inscrit (peu importe le statut) → refus.
    return Result.new(status: :already_registered) if @match.match_users.exists?(user: @user)

    # Match réservé aux joueuses : un non-femme (genre nil inclus) est bloqué.
    return Result.new(status: :gender_restricted) if gender_blocked?

    @match_user = @match.match_users.new(user: @user, role: "joueur", message: @message)
    @organizer  = @match.organizer_match_user&.user

    if @match.full?
      enroll_waiting_list
    elsif @match.manual_validation?
      enroll_manual
    else
      enroll_automatic
    end
  end

  private

  def gender_blocked?
    @match.genre_restriction == "feminin" && @user.genre != "femme"
  end

  # Cas 1 : match complet → file d'attente.
  def enroll_waiting_list
    @match_user.status = "waiting"
    return Result.new(status: :error, match_user: @match_user) unless @match_user.save

    notify(@organizer, "#{@user.display_name} s'est inscrit en file d'attente pour \"#{@match.title}\"")
    UserMailer.match_joined(@match, @user, status: "waiting").deliver_later
    Result.new(status: :waiting, match_user: @match_user)
  end

  # Cas 2 : validation manuelle → en attente de l'organisateur.
  # (Comme dans l'original, on ne traite pas l'échec de save ici.)
  def enroll_manual
    @match_user.status = "pending"
    @match_user.save
    notify(@organizer, "#{@user.display_name} veut rejoindre votre match \"#{@match.title}\"")
    UserMailer.match_joined(@match, @user, status: "pending").deliver_later
    Result.new(status: :pending, match_user: @match_user)
  end

  # Cas 3 : validation automatique → accepté immédiatement, sauf si la dernière
  # place vient d'être prise (recheck sous verrou).
  def enroll_automatic
    status_assigned = nil

    # with_lock : SELECT FOR UPDATE sur la ligne du match — un seul process évalue
    # le nombre de confirmés puis inscrit, éliminant la race condition. player_left
    # est recalculé par le callback de MatchUser au save.
    @match.with_lock do
      if @match.confirmed_players_count >= @match.players_needed.to_i
        # Place prise entre le check initial et maintenant → file d'attente.
        @match_user.status = "waiting"
        @match_user.save
        status_assigned = :waiting
      else
        @match_user.status = "approved"
        status_assigned = @match_user.save ? :approved : :error
      end
    end

    case status_assigned
    when :waiting
      notify(@organizer, "#{@user.display_name} s'est inscrit en file d'attente pour \"#{@match.title}\"")
      UserMailer.match_joined(@match, @user, status: "waiting").deliver_later
      Result.new(status: :waiting, match_user: @match_user)
    when :approved
      notify(@organizer, "#{@user.display_name} a rejoint votre match \"#{@match.title}\"")
      UserMailer.match_joined(@match, @user, status: "approved").deliver_later
      Result.new(status: :approved, match_user: @match_user)
    else
      Result.new(status: :error, match_user: @match_user)
    end
  end

  # Notification in-app à un utilisateur (rien si nil, ex. organisateur introuvable).
  def notify(user, message)
    return unless user

    Notification.create(user: user, message: message, link: match_path(@match))
  end
end
