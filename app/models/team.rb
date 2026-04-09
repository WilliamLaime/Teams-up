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
  # Sanitise le SVG du blason avant stockage pour éliminer toute injection XSS.
  # Le SVG est soumis via un champ caché rempli côté client — sans validation
  # serveur, n'importe qui pourrait injecter <script> ou des handlers "onload=".
  before_save :sanitize_badge_svg, if: -> { badge_svg_changed? && badge_svg.present? }

  # Quand une équipe est créée, on ajoute automatiquement le captain comme membre
  after_create :add_captain_as_member

  # Avant la suppression, on mémorise les ids des membres
  # car après destroy les team_members auront déjà été supprimés en cascade.
  before_destroy :cache_member_ids

  # Après la suppression de l'équipe, retire l'item de chat de la sidebar
  # pour chaque membre connecté, en temps réel via Turbo Stream.
  after_destroy :broadcast_chat_removal

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

  # Tags SVG autorisés — uniquement les éléments graphiques purs, aucun élément
  # actif (script, foreignObject, animate) ni événement (onclick, onload...).
  SVG_ALLOWED_TAGS = %w[
    svg g defs clipPath use
    circle ellipse rect line polyline polygon path
    text tspan
    title desc
  ].freeze

  # Attributs SVG autorisés — présentation et géométrie uniquement.
  # Les attributs "on*" (onclick, onmouseover…) et "href" vers javascript:
  # sont automatiquement exclus car absents de cette liste.
  SVG_ALLOWED_ATTRS = %w[
    xmlns viewBox width height
    fill fill-opacity fill-rule stroke stroke-width stroke-dasharray stroke-linecap stroke-linejoin
    d cx cy r rx ry x y x1 y1 x2 y2 points
    transform clip-path opacity
    text-anchor dominant-baseline font-size font-family font-weight font-style
    class id
  ].freeze

  # Sanitise le SVG avec la whitelist ci-dessus.
  # Rails::Html::SafeListSanitizer supprime tout tag/attribut absent de la liste,
  # ce qui élimine <script>, onload=, javascript: href, etc.
  def sanitize_badge_svg
    sanitizer = Rails::Html::SafeListSanitizer.new
    self.badge_svg = sanitizer.sanitize(
      badge_svg,
      tags:       SVG_ALLOWED_TAGS,
      attributes: SVG_ALLOWED_ATTRS
    )
  end

  # Ajoute le captain comme premier membre avec le rôle "captain"
  def add_captain_as_member
    team_members.create!(
      user:      captain,
      role:      "captain",
      joined_at: Time.current
    )
  end

  def cache_member_ids
    @member_ids_before_destroy = team_members.pluck(:user_id)
  end

  def broadcast_chat_removal
    @member_ids_before_destroy.to_a.each do |user_id|
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_conversations_#{user_id}",
        target: "sticky-team-convo-#{id}"
      )
    end
  end
end
