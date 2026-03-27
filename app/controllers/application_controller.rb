class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  include Pundit::Authorization

  # Pundit: allow-list approach
  # On n'utilise pas `only:` ni `except:` pour éviter l'erreur Rails 7.1
  # qui vérifie au chargement si l'action existe dans tous les sous-contrôleurs (Devise, etc.)
  # La condition est gérée dans les méthodes skip_* ci-dessous.
  after_action :verify_authorized, unless: :skip_pundit_verify_authorized?
  after_action :verify_policy_scoped, unless: :skip_pundit_verify_policy_scoped?

  # Si l'utilisateur n'est pas autorisé, on affiche un message et on le redirige
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Rend current_sport et multisport_mode? accessibles dans toutes les vues
  helper_method :current_sport, :multisport_mode?

  # Avant chaque action : charge les données de la modal de review si le flag est présent
  # Le flag est posé par after_sign_in_path_for juste après le login
  before_action :load_review_modal_data

  # Retourne true si l'utilisateur est en mode "Multisport" (tous les sports)
  def multisport_mode?
    user_signed_in? && session[:current_sport_id] == "all"
  end

  # Retourne le sport actuellement actif pour l'utilisateur connecté
  # Priorité : 1) mode multisport → nil  2) session  3) base  4) premier sport
  def current_sport
    return nil unless user_signed_in?
    # Mode multisport explicitement sélectionné → aucun sport actif
    return nil if multisport_mode?

    sport_id = session[:current_sport_id] || current_user.current_sport_id
    Sport.find_by(id: sport_id) || current_user.sports.first
  end

  private

  # Redirige l'utilisateur non autorisé avec un message d'alerte
  def user_not_authorized
    flash[:alert] = "Vous n'êtes pas autorisé à effectuer cette action."
    redirect_back(fallback_location: root_path)
  end

  # verify_authorized s'applique à toutes les actions SAUF index
  def skip_pundit_verify_authorized?
    skip_pundit? || action_name == "index"
  end

  # verify_policy_scoped s'applique UNIQUEMENT à l'action index
  def skip_pundit_verify_policy_scoped?
    skip_pundit? || action_name != "index"
  end

  # Ignore Pundit pour Devise et les pages publiques
  def skip_pundit?
    devise_controller? || params[:controller] =~ /(^(rails_)?admin)|(^pages$)/
  end

  # ── Système de modal post-match ───────────────────────────────────────────

  # Hook Devise : appelé automatiquement après chaque connexion réussie
  # On pose un flag en session pour déclencher la modal au prochain chargement de page
  def after_sign_in_path_for(resource)
    session[:show_review_modal] = true
    super
  end

  # Charge les données de la modal si le flag de session est présent
  # session.delete retire le flag → la modal ne s'affiche qu'une fois par connexion
  def load_review_modal_data
    return unless user_signed_in?

    # Sur la page show d'un match, on ne consomme pas le flag — la page a son propre bouton
    # Le flag sera affiché sur la prochaine page visitée
    return if controller_name == "matches" && action_name == "show"

    return unless session.delete(:show_review_modal)

    # Trouve les matchs terminés récents avec des joueurs non encore notés
    @pending_review_matches = find_pending_reviews_for_modal
  end

  # Retourne un tableau de { match:, users: [...] } pour la modal
  # Chaque élément = 1 match + liste des co-joueurs pas encore notés
  def find_pending_reviews_for_modal
    # Matchs où current_user a été approuvé
    my_match_ids = current_user.match_users.where(status: "approved").pluck(:match_id)
    return [] if my_match_ids.empty?

    # Filtre : terminé (>1h) ET dans les 7 derniers jours
    recent_completed_matches = Match.where(id: my_match_ids)
                                    .where("(date + time) < ?", Time.current - 1.hour)
                                    .where("(date + time) > ?", Time.current - 7.days - 1.hour)

    return [] if recent_completed_matches.empty?

    # IDs des joueurs déjà notés par current_user (toutes périodes confondues)
    already_reviewed = Avis.where(reviewer_id: current_user.id)
                           .pluck(:reviewed_user_id, :match_id)
                           .map { |uid, mid| "#{uid}-#{mid}" }

    # IDs des matchs pour lesquels current_user a déjà voté pour l'homme du match
    already_voted_match_ids = MatchVote.where(voter_id: current_user.id).pluck(:match_id)

    result = []

    recent_completed_matches.each do |match|
      # Co-joueurs approuvés dans ce match (sauf current_user)
      co_player_ids = match.match_users
                           .where(status: "approved")
                           .where.not(user_id: current_user.id)
                           .pluck(:user_id)

      # Co-joueurs pas encore notés dans CE match
      pending_ids = co_player_ids.reject { |uid| already_reviewed.include?("#{uid}-#{match.id}") }

      # A-t-on déjà voté pour l'homme du match de ce match ?
      has_voted = already_voted_match_ids.include?(match.id)

      # Le vote homme du match n'a du sens que si des co-joueurs existent
      # (évite d'afficher la section si le créateur est seul ou si co_player_ids est vide)
      can_vote_homme = !has_voted && co_player_ids.any?

      # On inclut le match si des reviews sont pending OU si on peut encore voter homme du match
      next unless pending_ids.any? || can_vote_homme

      pending_users  = User.where(id: pending_ids).includes(:profil)
      all_co_players = User.where(id: co_player_ids).includes(:profil)

      result << {
        match: match,
        users: pending_users, # joueurs à noter (review)
        all_co_players: all_co_players, # tous les joueurs (vote homme du match)
        has_voted: has_voted, # true si déjà voté pour ce match
        can_vote_homme: can_vote_homme # true si la section homme du match doit s'afficher
      }
    end

    result
  end
end
