class TeamInvitation < ApplicationRecord
  # ── Associations ───────────────────────────────────────────────────────────
  belongs_to :team
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  # ── Constantes ─────────────────────────────────────────────────────────────
  STATUSES = %w[pending accepted refused].freeze

  # ── Validations ────────────────────────────────────────────────────────────
  validates :status, inclusion: { in: STATUSES }

  # Un user ne peut avoir qu'une seule invitation en attente par équipe (pas de blocage si refusée/acceptée)
  validates :invitee_id, uniqueness: {
    scope:      :team_id,
    conditions: -> { where(status: "pending") },
    message:    "a déjà une invitation en attente pour cette équipe"
  }

  # ── Scopes ─────────────────────────────────────────────────────────────────
  scope :pending,  -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :refused,  -> { where(status: "refused") }

  # ── Méthodes d'instance ────────────────────────────────────────────────────

  def pending?
    status == "pending"
  end

  def accepted?
    status == "accepted"
  end

  def refused?
    status == "refused"
  end
end
