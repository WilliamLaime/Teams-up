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
end
