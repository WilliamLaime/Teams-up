# ── Modèle TournamentRound ────────────────────────────────────────────────────
# Une ronde d'un tournoi (Lot 3). Regroupe les appariements générés d'un coup :
#   - phase "swiss"   : une ronde de ronde suisse (tirage intégral) ;
#   - phase "bracket" : un tour du tableau final (élimination directe).
class TournamentRound < ApplicationRecord
  belongs_to :tournament
  has_many :tournament_matches, dependent: :destroy

  PHASES   = %w[swiss bracket].freeze
  STATUSES = %w[pending in_progress completed].freeze

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :phase,  inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }

  scope :swiss,   -> { where(phase: "swiss") }
  scope :bracket, -> { where(phase: "bracket") }
  scope :ordered, -> { order(:number) }

  # Ronde terminée : tous ses matchs ont un vainqueur (les byes sont décidés d'office).
  def complete?
    tournament_matches.all?(&:decided?)
  end
end
