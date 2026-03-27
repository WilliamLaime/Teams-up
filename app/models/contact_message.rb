# Modèle pour les messages envoyés via le formulaire de contact.
# Le formulaire est public — pas de relation avec User.
class ContactMessage < ApplicationRecord
  # ── Validations ──────────────────────────────────────────────────────────
  # Tous les champs sont obligatoires
  validates :prenom,  presence: true
  validates :nom,     presence: true
  validates :email,   presence: true,
                      format: { with: URI::MailTo::EMAIL_REGEXP, message: "n'est pas valide" }
  validates :sujet,   presence: true
  validates :message, presence: true

  # ── Scopes ───────────────────────────────────────────────────────────────
  # Messages non lus — utilisé dans l'admin pour le badge compteur
  scope :unread, -> { where(lu: false) }
  # Tri du plus récent au plus ancien
  scope :recent, -> { order(created_at: :desc) }
end
