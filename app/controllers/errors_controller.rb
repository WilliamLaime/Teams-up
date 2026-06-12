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
  # Appelée quand un match (ou n'importe quelle ressource) n'existe plus.
  # On force le format HTML : des bots scannent des URLs WordPress en XML
  # (ex: /wp-includes/wlwmanifest.xml) — sans ce forçage, Rails cherche un
  # template errors/not_found.xml.erb qui n'existe pas et lève un 500.
  def not_found
    render status: :not_found, formats: [:html]
  end

  # GET /500 — erreur serveur interne
  # Appelée quand Rails lève une exception non gérée.
  # Même raison que not_found : on force HTML pour éviter un double 500.
  def internal_server_error
    render status: :internal_server_error, formats: [:html]
  end
end
