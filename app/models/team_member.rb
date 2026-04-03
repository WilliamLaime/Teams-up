class TeamMember < ApplicationRecord
  # ── Associations ───────────────────────────────────────────────────────────
  belongs_to :team
  belongs_to :user

  # ── Constantes ─────────────────────────────────────────────────────────────
  ROLES = %w[captain member].freeze

  # ── Validations ────────────────────────────────────────────────────────────
  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :team_id, message: "est déjà membre de cette équipe" }

  # ── Méthodes d'instance ────────────────────────────────────────────────────

  def captain?
    role == "captain"
  end

  def member?
    role == "member"
  end
end
