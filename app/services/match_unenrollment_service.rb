# ── Service MatchUnenrollmentService ──────────────────────────────────────────
# Encapsule la logique métier de DÉSINSCRIPTION d'un joueur, extraite de
# MatchUsersController#destroy afin de la réutiliser depuis un autre point
# d'entrée (désinscription déclenchée depuis Slack). C'est le pendant de
# MatchEnrollmentService.
#
# Responsabilités (métier pur, sans HTTP) :
#   - retrouver l'inscription du joueur (no-op si absent) ;
#   - si la place était approuvée : promouvoir le 1er de la file d'attente
#     (sous verrou), puis prévenir l'organisateur du départ par email ;
#   - détruire l'inscription (le callback MatchUser recalcule les places
#     et rafraîchit la carte Slack).
#
# Ce qui reste au controller web : `authorize`, les broadcasts Turbo temps réel
# (départ affiché à l'organisateur), le flash et la redirection. Le controller
# mappe simplement `result.was_approved` vers ses broadcasts.
#
# Utilisation :
#   result = MatchUnenrollmentService.new(match: @match, user: current_user).call
#   result.status # => :left | :not_registered
class MatchUnenrollmentService
  # match_path n'est pas dispo hors controller/vue → on inclut les helpers de
  # routes pour construire le lien des notifications (promotion depuis la file).
  include Rails.application.routes.url_helpers

  Result = Struct.new(:status, :leaving_user, :was_approved, keyword_init: true)

  def initialize(match:, user:)
    @match = match
    @user  = user
  end

  def call
    match_user = @match.match_users.find_by(user: @user)
    return Result.new(status: :not_registered) unless match_user

    leaving_user = match_user.user
    was_approved = match_user.approved?

    # Une place approuvée se libère → on promeut d'abord le 1er en file d'attente
    # (avant le destroy, comme le controller web), puis on prévient l'organisateur.
    promote_next_in_line if was_approved

    match_user.destroy

    UserMailer.match_player_left(@match, leaving_user).deliver_later if was_approved

    Result.new(status: :left, leaving_user: leaving_user, was_approved: was_approved)
  end

  private

  # Promeut le prochain joueur en file d'attente quand une place se libère.
  # with_lock (SELECT FOR UPDATE) : évite que deux départs simultanés promeuvent
  # deux personnes pour une seule place libérée.
  def promote_next_in_line
    promoted_record = nil

    @match.with_lock do
      next_in_line = @match.match_users.where(status: "waiting").order(created_at: :asc).first
      if next_in_line
        # Le passage à "approved" déclenche le recalcul de player_left (la place
        # reste occupée, reprise par le promu).
        next_in_line.update(status: "approved")
        promoted_record = next_in_line
      end
      # Si personne n'attend : le destroy de l'inscription rendra la place.
    end

    return unless promoted_record

    message = "🎉 Une place s'est libérée ! Tu as été automatiquement inscrit au match \"#{@match.title}\"."
    notify(promoted_record.user, message)
    UserMailer.match_status_changed(promoted_record, accepted: true).deliver_later
  end

  # Notification in-app (rien si user nil).
  def notify(user, message)
    return unless user

    Notification.create(user: user, message: message, link: match_path(@match))
  end
end
