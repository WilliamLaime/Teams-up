class Friendship < ApplicationRecord
  # L'utilisateur qui a envoyé la demande d'ami
  belongs_to :user
  # L'utilisateur qui a reçu la demande (même table users, clé étrangère "friend_id")
  belongs_to :friend, class_name: "User"

  # Statuts possibles pour une demande d'ami
  STATUSES = %w[pending accepted declined].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :friend_id, presence: true
  validate :cannot_friend_yourself

  # ── Scopes pour filtrer par statut ────────────────────────────────────────
  # Demandes en attente (pas encore répondues)
  scope :pending,  -> { where(status: "pending") }
  # Demandes acceptées (les deux sont amis)
  scope :accepted, -> { where(status: "accepted") }
  # Demandes refusées
  scope :declined, -> { where(status: "declined") }

  # ── Méthodes utilitaires ──────────────────────────────────────────────────
  def pending?  = status == "pending"
  def accepted? = status == "accepted"
  def declined? = status == "declined"

  private

  def cannot_friend_yourself
    errors.add(:friend_id, "Vous ne pouvez pas vous ajouter vous-même") if friend_id == user_id
  end
end
