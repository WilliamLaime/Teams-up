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

  # État suisse dérivé d'un bilan V/D donné (mêmes seuils que ci-dessus). Utilisé
  # par SwissPairing pour l'état réel du joueur ET par le ruban de rondes (onglet
  # Matchs) pour colorer les pastilles de bilan par groupe en en-tête de colonne
  # — d'où la version "pure" (sans lire l'état persisté d'un joueur en particulier).
  def self.state_for(wins, losses)
    return "qualified" if wins >= WINS_TO_QUALIFY
    return "eliminated" if losses >= LOSSES_TO_ELIMINATE

    "active"
  end

  # Rôle dans le tournoi. "joueur" = participant qui occupe une place ;
  # "co_organisateur" = co-gestionnaire (mêmes droits que l'admin sauf suppression
  # / édition des métadonnées), sans occuper de place de joueur.
  ROLES = %w[joueur co_organisateur].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }, allow_nil: true
  validates :state, inclusion: { in: STATES }

  # Clôture réactive des inscriptions dès que le tournoi devient complet — même
  # pattern que Match#recompute_player_left!. Pas de hook after_destroy : quitter
  # un tournoi ne peut jamais le rendre plus complet.
  after_save :close_tournament_if_full

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

  # Points de classement (Lot 6) : barème V/N/D du sport (cf. Sport#ranking_points_rules).
  # Sports de raquette (pas de barème dédié, ronde suisse/poules) → 1 pt par victoire,
  # le système de points standard des tournois suisses.
  def ranking_points
    rules = tournament.sport&.ranking_points_rules
    return wins if rules.nil?

    (wins * rules[:win]) + (draws * rules[:draw]) + (losses * rules[:loss])
  end

  # Nom affiché du joueur (délègue au profil de l'utilisateur).
  def display_name = user.display_name

  private

  def close_tournament_if_full
    tournament.close_registrations_if_full!
  end
end
