class TeamInvitation < ApplicationRecord
  # ── Associations ───────────────────────────────────────────────────────────
  belongs_to :team
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"
  # Membre non-capitaine qui a proposé ce joueur (nil si invitation directe du captain)
  belongs_to :proposed_by, class_name: "User", optional: true

  # ── Constantes ─────────────────────────────────────────────────────────────
  # pending   : invitation envoyée par le capitaine, en attente de réponse de l'invité
  # accepted  : invitation/demande acceptée (un TeamMember a été créé)
  # refused   : invitation refusée par l'invité
  # proposed  : un membre propose un ami au capitaine (en attente de validation captain)
  # requested : un joueur demande spontanément à rejoindre l'équipe (en attente captain)
  STATUSES = %w[pending accepted refused proposed requested].freeze

  # ── Validations ────────────────────────────────────────────────────────────
  validates :status, inclusion: { in: STATUSES }

  # Un user ne peut avoir qu'une seule invitation pending par équipe
  validates :invitee_id, uniqueness: {
    scope: :team_id,
    conditions: -> { where(status: "pending") },
    message: "a déjà une invitation en attente pour cette équipe"
  }

  # Un user ne peut avoir qu'une seule proposition en attente par équipe
  validates :invitee_id, uniqueness: {
    scope: :team_id,
    conditions: -> { where(status: "proposed") },
    message: "a déjà une proposition en attente pour cette équipe"
  }

  # Un user ne peut avoir qu'une seule demande d'adhésion en attente par équipe
  validates :invitee_id, uniqueness: {
    scope: :team_id,
    conditions: -> { where(status: "requested") },
    message: "a déjà une demande en attente pour cette équipe"
  }

  # ── Scopes ─────────────────────────────────────────────────────────────────
  scope :pending,   -> { where(status: "pending") }
  scope :accepted,  -> { where(status: "accepted") }
  scope :refused,   -> { where(status: "refused") }
  scope :proposed,  -> { where(status: "proposed") }
  scope :requested, -> { where(status: "requested") }

  # ── Méthodes d'instance ────────────────────────────────────────────────────

  def pending?   = status == "pending"
  def accepted?  = status == "accepted"
  def refused?   = status == "refused"
  def proposed?  = status == "proposed"
  def requested? = status == "requested"
end
