# ── Modèle TournamentRound ────────────────────────────────────────────────────
# Une ronde d'un tournoi. Regroupe les appariements générés d'un coup :
#   - phase "swiss"   : une ronde de ronde suisse (tirage intégral, Lot 3) ;
#   - phase "league"  : une journée de championnat (round-robin intégral, Lot 5) ;
#   - phase "pool"    : une journée de poules (round-robin par poule, Lot 5) ;
#   - phase "bracket" : un tour du tableau final / playoffs (élimination directe).
#
# Critérium Fédéral (FFTT) — trois phases de plus :
#   - phase "barrage"        : les 2es de poule contre les 3es d'une autre poule ;
#   - phase "consolation"    : la consolante (« KO »), second tableau complet ;
#   - phase "classification" : les mini-tableaux de classement (3e/4e, 5e-8e…).
#
# La colonne `branch` distingue deux suites de tours CONCURRENTES dans une même
# phase : le match pour la 3e place ("ok:3-4") et le mini-tableau des places 5 à 8
# ("ok:5-8") sont tous deux en phase "classification" au tour n°1. Sans `branch`,
# l'index unique (tournoi, phase, numéro) les rendrait mutuellement exclusifs.
class TournamentRound < ApplicationRecord
  belongs_to :tournament
  has_many :tournament_matches, dependent: :destroy

  PHASES   = %w[swiss league pool barrage bracket consolation classification].freeze
  STATUSES = %w[pending in_progress completed].freeze

  # Branche par défaut : la suite de tours principale d'une phase.
  MAIN_BRANCH = "main"

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :phase,  inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }
  validates :branch, presence: true

  scope :swiss,   -> { where(phase: "swiss") }
  scope :league,  -> { where(phase: "league") }
  scope :pool,    -> { where(phase: "pool") }
  scope :bracket, -> { where(phase: "bracket") }
  scope :barrage,        -> { where(phase: "barrage") }
  scope :consolation,    -> { where(phase: "consolation") }
  scope :classification, -> { where(phase: "classification") }
  # Suite de tours principale d'une phase (exclut les mini-tableaux de classement).
  scope :main_branch, -> { where(branch: MAIN_BRANCH) }
  # Toutes les phases postérieures aux poules (cf. Tournament::FINAL_PHASES).
  scope :final_phase, -> { where(phase: Tournament::FINAL_PHASES) }
  scope :ordered, -> { order(:number) }

  # Ronde terminée : tous ses matchs ont un résultat définitif (victoire, nul ou bye —
  # PAS `decided?`, qui exige un vainqueur : un match nul n'en a pas, cf. Lot 6)
  # ET tous ceux qu'elle doit compter existent.
  #
  # La seconde condition ne concerne que les tours de tableau construits AU FUR ET
  # À MESURE (cf. BracketBuilder#advance! en mode incrémental) : un quart créé
  # avant l'autre ne doit pas faire passer la colonne pour terminée, sinon
  # CriteriumFlow#close_finished_rounds! la verrouille et le match restant devient
  # injouable. `expected_matches` à nil = tour généré d'un bloc (poules, ronde
  # suisse, championnat, barrages) → comportement historique inchangé.
  def complete?
    matches = tournament_matches.to_a
    return false if expected_matches.present? && matches.size < expected_matches

    matches.all? { |m| m.status == "completed" }
  end
end
