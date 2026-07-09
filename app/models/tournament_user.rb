# ── Modèle TournamentUser ─────────────────────────────────────────────────────
# Inscription d'un utilisateur à un tournoi (table de jointure).
# Équivalent minimal de MatchUser pour le Lot 1 : rejoindre / quitter.
class TournamentUser < ApplicationRecord
  belongs_to :user
  belongs_to :tournament

  # "approved" = inscrit confirmé ; "pending" réservé à une future validation manuelle.
  STATUSES = %w[approved pending].freeze

  # Rôle dans le tournoi. "joueur" = participant qui occupe une place ;
  # "co_organisateur" = co-gestionnaire (mêmes droits que l'admin sauf suppression
  # / édition des métadonnées), sans occuper de place de joueur.
  ROLES = %w[joueur co_organisateur].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }, allow_nil: true

  scope :approved, -> { where(status: "approved") }
  # Uniquement les inscrits qui occupent une place de joueur.
  scope :players,  -> { where(role: "joueur") }
end
