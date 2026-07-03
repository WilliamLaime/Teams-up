# Modèle Article — représente un article de blog.
# Les articles sont accessibles publiquement via /blog/:slug.
# Un article avec published_at NULL est un brouillon (non visible publiquement).
class Article < ApplicationRecord
  # ── Validations ────────────────────────────────────────────────────────────

  validates :title,            presence: true
  validates :slug,             presence: true, uniqueness: { case_sensitive: false },
                               format: { with: /\A[a-z0-9-]+\z/, message: "ne doit contenir que des lettres minuscules, chiffres et tirets" }
  validates :body,             presence: true
  validates :meta_description, length: { maximum: 160 }, allow_blank: true

  # ── Callbacks ──────────────────────────────────────────────────────────────

  # Génère automatiquement le slug depuis le titre si non renseigné
  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  # Calcule le temps de lecture estimé avant chaque sauvegarde
  before_save :estimate_reading_time

  # ── Scopes ─────────────────────────────────────────────────────────────────

  # Articles publiés : published_at non NULL et dans le passé
  scope :published, -> { where.not(published_at: nil).where("published_at <= ?", Time.current) }

  # Ordre chronologique inversé (plus récent en premier)
  scope :recent, -> { order(published_at: :desc) }

  # Filtrage par catégorie
  scope :by_category, ->(cat) { where(category: cat) }

  # ── Méthodes d'instance ────────────────────────────────────────────────────

  # Retourne true si l'article est publié (published_at présent et dans le passé)
  def published?
    published_at.present? && published_at <= Time.current
  end

  # Publie l'article maintenant (si pas encore publié)
  def publish!
    update(published_at: Time.current) unless published?
  end

  # Dépublie l'article (repasse en brouillon)
  def unpublish!
    update(published_at: nil)
  end

  # Retourne les catégories disponibles (liste statique pour l'instant)
  def self.categories
    %w[conseils sport équipe matchs actualités]
  end

  private

  # Génère un slug URL-friendly depuis le titre :
  # "Comment trouver un match de foot ?" → "comment-trouver-un-match-de-foot"
  def generate_slug
    self.slug = title
                .downcase
                .gsub(/[àáâãäå]/, "a").gsub(/[èéêë]/, "e").gsub(/[ìíîï]/, "i")
                .gsub(/[òóôõö]/, "o").gsub(/[ùúûü]/, "u").gsub(/ç/, "c")
                .gsub(/[^a-z0-9\s-]/, "")
                .gsub(/\s+/, "-")
                .gsub(/-+/, "-")
                .strip
  end

  # Estime le temps de lecture : ~200 mots par minute
  def estimate_reading_time
    word_count = body.to_s.split.size
    self.reading_time_minutes = [(word_count / 200.0).ceil, 1].max
  end
end
