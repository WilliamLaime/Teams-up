# ── Modèle TournamentMatch ────────────────────────────────────────────────────
# Un match d'un tournoi (Lot 3) : oppose deux inscriptions (tournament_users).
# player_b nul = bye (exempt) → player_a est déclaré vainqueur d'office.
# Au Lot 3 on ne stocke que le vainqueur (résultat V/D). Le détail set-par-set
# viendra au Lot 4.
class TournamentMatch < ApplicationRecord
  belongs_to :tournament_round
  belongs_to :player_a, class_name: "TournamentUser"
  belongs_to :player_b, class_name: "TournamentUser", optional: true
  belongs_to :winner,   class_name: "TournamentUser", optional: true

  has_one :tournament, through: :tournament_round

  STATUSES = %w[pending completed].freeze

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate  :winner_is_a_player

  # Un bye est gagné d'office par player_a dès sa création.
  before_validation :resolve_bye, on: :create

  # Match décidé : un vainqueur est connu (inclut les byes).
  def decided? = winner_id.present?

  # Les deux inscriptions en lice (compacte le bye).
  def players = [player_a, player_b].compact

  # Le perdant (nil sur un bye ou un match non décidé).
  def loser
    return nil if is_bye || winner_id.blank?

    winner_id == player_a_id ? player_b : player_a
  end

  private

  # Le vainqueur doit être l'un des deux joueurs du match.
  def winner_is_a_player
    return if winner_id.blank?
    return if winner_id == player_a_id || winner_id == player_b_id

    errors.add(:winner, "doit être l'un des deux joueurs du match")
  end

  # Bye : pas d'adversaire → player_a gagne, match clôturé immédiatement.
  def resolve_bye
    return unless is_bye

    self.player_b_id = nil
    self.winner_id ||= player_a_id
    self.status = "completed"
  end
end
