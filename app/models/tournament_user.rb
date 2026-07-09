# ── Modèle TournamentUser ─────────────────────────────────────────────────────
# Inscription d'un utilisateur à un tournoi (table de jointure).
# Équivalent minimal de MatchUser pour le Lot 1 : rejoindre / quitter.
class TournamentUser < ApplicationRecord
  belongs_to :user
  belongs_to :tournament

  # "approved" = inscrit confirmé ; "pending" réservé à une future validation manuelle.
  STATUSES = %w[approved pending].freeze

  # Parcours du joueur dans la phase suisse (Lot 3) :
  # "active" (encore en lice) → "qualified" (3 V, passe au tableau final) | "eliminated" (3 D).
  STATES = %w[active qualified eliminated].freeze

  # Seuils de la ronde suisse : 3 victoires pour se qualifier, 3 défaites pour être éliminé.
  WINS_TO_QUALIFY = 3
  LOSSES_TO_ELIMINATE = 3

  # Rôle dans le tournoi. "joueur" = participant qui occupe une place ;
  # "co_organisateur" = co-gestionnaire (mêmes droits que l'admin sauf suppression
  # / édition des métadonnées), sans occuper de place de joueur.
  ROLES = %w[joueur co_organisateur].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }, allow_nil: true
  validates :state, inclusion: { in: STATES }

  scope :approved, -> { where(status: "approved") }
  # Uniquement les inscrits qui occupent une place de joueur.
  scope :players,  -> { where(role: "joueur") }
  # Parcours dans la phase suisse.
  scope :active,     -> { where(state: "active") }
  scope :qualified,  -> { where(state: "qualified") }
  scope :eliminated, -> { where(state: "eliminated") }

  # ── Prédicats de parcours (Lot 3) ────────────────────────────────────────────
  def active?     = state == "active"
  def qualified?  = state == "qualified"
  def eliminated? = state == "eliminated"

  # Nom affiché du joueur (délègue au profil de l'utilisateur).
  def display_name = user.display_name
end
