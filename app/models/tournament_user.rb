# ── Modèle TournamentUser ─────────────────────────────────────────────────────
# Inscription d'un utilisateur à un tournoi (table de jointure).
# Équivalent minimal de MatchUser pour le Lot 1 : rejoindre / quitter.
class TournamentUser < ApplicationRecord
  belongs_to :user
  belongs_to :tournament

  # "approved" = inscrit confirmé ; "pending" réservé à une future validation manuelle.
  STATUSES = %w[approved pending].freeze

  # Parcours du joueur (Lot 3, étendu Lot 5) :
  # "active" (encore en lice) → "qualified" (passe au tableau final) | "eliminated"
  # (sorti par le score) ; "withdrawn" = a déclaré forfait / abandonné (Lot 5).
  STATES = %w[active qualified eliminated withdrawn].freeze

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
  scope :withdrawn,  -> { where(state: "withdrawn") }

  # ── Prédicats de parcours (Lot 3, étendu Lot 5) ──────────────────────────────
  def active?     = state == "active"
  def qualified?  = state == "qualified"
  def eliminated? = state == "eliminated"
  def withdrawn?  = state == "withdrawn"

  # ── Départage fin (Lot 4 — seeding réel) ─────────────────────────────────────
  # Set average / point average : différentiels servant à classer les joueurs à
  # égalité de victoires (appariement suisse + seeding du tableau final).
  def set_average   = sets_won - sets_lost
  def point_average = points_won - points_lost

  # Nom affiché du joueur (délègue au profil de l'utilisateur).
  def display_name = user.display_name
end
