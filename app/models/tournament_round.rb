# ── Modèle TournamentRound ────────────────────────────────────────────────────
# Une ronde d'un tournoi. Regroupe les appariements générés d'un coup :
#   - phase "swiss"   : une ronde de ronde suisse (tirage intégral, Lot 3) ;
#   - phase "league"  : une journée de championnat (round-robin intégral, Lot 5) ;
#   - phase "pool"    : une journée de poules (round-robin par poule, Lot 5) ;
#   - phase "bracket" : un tour du tableau final / playoffs (élimination directe).
class TournamentRound < ApplicationRecord
  belongs_to :tournament
  has_many :tournament_matches, dependent: :destroy

  PHASES   = %w[swiss league pool bracket].freeze
  STATUSES = %w[pending in_progress completed].freeze

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :phase,  inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }

  scope :swiss,   -> { where(phase: "swiss") }
  scope :league,  -> { where(phase: "league") }
  scope :pool,    -> { where(phase: "pool") }
  scope :bracket, -> { where(phase: "bracket") }
  scope :ordered, -> { order(:number) }

  # Ronde terminée : tous ses matchs ont un résultat définitif (victoire, nul ou bye —
  # PAS `decided?`, qui exige un vainqueur : un match nul n'en a pas, cf. Lot 6).
  def complete?
    tournament_matches.all? { |m| m.status == "completed" }
  end
end
