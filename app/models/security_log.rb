# Modèle SecurityLog : enregistre tous les événements de sécurité de l'application.
# Chaque ligne = un événement (connexion réussie, échec, blocage rack-attack, inscription, etc.)
#
# Utilisation depuis un controller :
#   SecurityLog.log("login_failure", request, email_tente: "foo@bar.com")
#   SecurityLog.log("login_success", request, user: current_user)
class SecurityLog < ApplicationRecord
  # Lien vers l'utilisateur concerné (peut être nil si on ne connaît pas encore l'utilisateur)
  belongs_to :user, optional: true

  # Liste exhaustive des types d'événements autorisés
  # Centralisée ici pour éviter les fautes de frappe dans les controllers
  EVENT_TYPES = %w[
    login_success
    login_failure
    rack_attack_throttle
    password_reset_request
    signup
    google_login
    account_deletion
    admin_access
  ].freeze

  # Validation : le type d'événement doit être dans la liste ci-dessus
  validates :event_type, inclusion: { in: EVENT_TYPES }

  # ── Scopes ──────────────────────────────────────────────────────────────────

  # Trie du plus récent au plus ancien (utile dans l'admin)
  scope :recent, -> { order(created_at: :desc) }

  # Filtre par type d'événement
  scope :by_type, ->(type) { where(event_type: type) }

  # ── Rétention (RGPD) ────────────────────────────────────────────────────────
  #
  # Un SecurityLog contient une adresse IP et un user-agent : ce sont des données
  # personnelles. Le RGPD impose une durée de conservation définie ET appliquée
  # (principe de minimisation, art. 5). La CNIL recommande 6 mois à 1 an pour des
  # journaux techniques de sécurité : on retient 12 mois.
  #
  # La purge se lance avec `rake security_logs:purge` (voir lib/tasks/security_logs.rake).
  # Durée documentée dans docs/SECURITE-RGPD.md.
  RETENTION_PERIOD = 12.months

  # Lignes dont la durée de conservation est dépassée
  scope :purgeable, ->(period = RETENTION_PERIOD) { where(created_at: ...period.ago) }

  # ── Méthode de classe pour créer un log facilement ──────────────────────────
  #
  # Paramètres :
  #   event_type   – string du type d'événement (ex: "login_failure")
  #   request      – objet ActionDispatch::Request (disponible dans tous les controllers)
  #   user:        – l'utilisateur concerné (optionnel, keyword argument)
  #   **details    – toutes autres données à stocker en JSON (ex: email_tente:, throttle_name:)
  #
  # Exemple :
  #   SecurityLog.log("login_failure", request, email_tente: "hacker@evil.com")
  #   SecurityLog.log("login_success", request, user: @user, provider: "google")
  def self.log(event_type, request, user: nil, **details)
    create!(
      event_type: event_type,
      user: user,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      details: details
    )
  rescue StandardError => e
    # Si le log échoue (ex: base indisponible), on n'interrompt PAS l'action principale.
    # On écrit juste l'erreur dans le log serveur pour investigation.
    Rails.logger.error("[SecurityLog] Échec de création du log : #{e.message}")
  end
end
