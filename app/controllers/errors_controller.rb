# Ce controller gère les pages d'erreur personnalisées de l'application.
# Il est appelé automatiquement par Rails quand une exception se produit
# (configuré dans config/application.rb via config.exceptions_app).
class ErrorsController < ApplicationController
  # On désactive l'authentification Devise pour ces pages —
  # un utilisateur non connecté doit aussi voir la 404 proprement
  skip_before_action :authenticate_user!, raise: false

  # Pundit exige qu'on appelle authorize dans chaque action.
  # Les pages d'erreur n'ont pas de ressource à autoriser, donc on désactive cette vérification.
  skip_after_action :verify_authorized, raise: false
  skip_after_action :verify_policy_scoped, raise: false

  # GET /404 — page introuvable
  # Appelée quand un match (ou n'importe quelle ressource) n'existe plus
  def not_found
    # On force le status HTTP 404 (Not Found)
    render status: :not_found
  end

  # GET /500 — erreur serveur interne
  # Appelée quand Rails lève une exception non gérée
  def internal_server_error
    # On force le status HTTP 500 (Internal Server Error)
    render status: :internal_server_error
  end
end
