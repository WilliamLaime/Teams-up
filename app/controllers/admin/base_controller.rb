# Controller de base pour tous les controllers de l'espace admin.
# Tous les controllers admin doivent hériter de celui-ci pour être protégés.
# La sécurité est centralisée ici — si un user n'est pas admin, il est renvoyé à l'accueil.
module Admin
  class BaseController < ApplicationController
    # Vérifie que l'utilisateur est admin avant chaque action
    before_action :require_admin!

    # Journalise chaque accès admin (traçabilité RGPD, art. 5.2 « responsabilité »).
    # after_action : ne s'exécute QUE si le before_action require_admin! n'a pas
    # interrompu la chaîne — donc uniquement pour les admins réellement autorisés.
    after_action :log_admin_access

    private

    # Redirige vers l'accueil si l'utilisateur n'est pas admin
    # current_user&.admin? : le & évite une erreur si current_user est nil (user non connecté)
    def require_admin!
      redirect_to root_path, alert: "Accès refusé." unless current_user&.admin?
    end

    # Enregistre qui a accédé à quelle section de l'admin, quand et depuis quelle IP.
    # Objectif RGPD : pouvoir prouver, en cas de contrôle ou d'incident, quels admins
    # ont consulté des données personnelles (emails, logs de connexion, messages…).
    #
    # SecurityLog.log rescue toute erreur en interne : un échec de log n'interrompt
    # jamais l'action principale et ne casse jamais la page.
    def log_admin_access
      SecurityLog.log(
        "admin_access",
        request,
        user: current_user,
        section: controller_name,             # ex: "users", "dashboard", "security_logs"
        action: action_name,                  # ex: "index", "confirm", "destroy"
        method: request.request_method,       # GET, POST, DELETE…
        **audit_relevant_params
      )
    end

    # Ne conserve que les paramètres utiles à l'audit (et jamais de données sensibles) :
    #   - id  : la ressource ciblée (ex: quel utilisateur a été confirmé)
    #   - q   : la recherche effectuée (révèle quel email/nom l'admin a cherché)
    # request.filtered_parameters respecte config.filter_parameters (mot de passe, etc.).
    def audit_relevant_params
      request.filtered_parameters
             .slice("id", "q")
             .reject { |_k, v| v.blank? }
             .symbolize_keys
    end
  end
end
