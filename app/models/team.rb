class Team < ApplicationRecord
  # ── Associations ───────────────────────────────────────────────────────────
  belongs_to :captain, class_name: "User"

  has_many :team_members,      dependent: :destroy
  has_many :members,           through: :team_members, source: :user
  has_many :team_invitations,  dependent: :destroy

  # Matchs créés par cette équipe
  has_many :matches, foreign_key: :team_id, dependent: :nullify

  # Messages du chat d'équipe
  has_many :messages, dependent: :destroy

  # Blason uploadé via Active Storage (alternative au SVG généré)
  has_one_attached :badge_image

  # Image de couverture (bannière en haut de la page équipe)
  has_one_attached :cover_image

  validates :cover_image,
            content_type: { in: %w[image/jpeg image/png image/webp], message: "doit être un JPG, PNG ou WebP" },
            size: { less_than: 5.megabytes, message: "ne doit pas dépasser 5 Mo" },
            if: -> { cover_image.attached? }

  # ── Validations ────────────────────────────────────────────────────────────
  validates :name, presence: true, length: { maximum: 50 }

  # Unicité du nom par captain (pas deux équipes du même nom pour un même user)
  validates :name, uniqueness: { scope: :captain_id, message: "Vous avez déjà une équipe avec ce nom" }

  validates :badge_image,
            content_type: { in: %w[image/jpeg image/png], message: "doit être un JPG ou PNG" },
            size: { less_than: 2.megabytes, message: "ne doit pas dépasser 2 Mo" },
            if: -> { badge_image.attached? }

  # ── Callbacks ──────────────────────────────────────────────────────────────
  # Quand une équipe est créée, on ajoute automatiquement le captain comme membre
  after_create :add_captain_as_member

  # ── Méthodes d'instance ────────────────────────────────────────────────────

  # Retourne vrai si l'user donné est le captain de l'équipe
  def captain?(user)
    captain_id == user.id
  end

  # Retourne vrai si l'user donné est membre (incluant le captain)
  def member?(user)
    members.include?(user)
  end

  # Retourne vrai si l'user a déjà une invitation en attente pour cette équipe
  def invitation_pending_for?(user)
    team_invitations.exists?(invitee: user, status: "pending")
  end

  # Nombre total de membres
  def members_count
    team_members.count
  end

  # Retourne l'URL ou les données du blason à afficher
  # Priorité : image uploadée > SVG généré > nil
  def badge_display
    return nil unless badge_image.attached? || badge_svg.present?
    badge_image.attached? ? :image : :svg
  end

  private

  # Ajoute le captain comme premier membre avec le rôle "captain"
  def add_captain_as_member
    team_members.create!(
      user:      captain,
      role:      "captain",
      joined_at: Time.current
    )
  end
end
