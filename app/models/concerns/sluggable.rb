# ── Concern Sluggable ─────────────────────────────────────────────────────────
# Donne à un modèle une URL « propre » basée sur un slug lisible plutôt que sur
# son id numérique. Ex : /matches/foot-5v5-paris-a1b2c3 au lieu de /matches/42.
#
# Le slug = base lisible (parameterize du champ source) + suffixe court aléatoire,
# ce qui garantit l'unicité même quand le champ source n'est pas unique
# (title de match nullable/non-unique ; name d'équipe unique par capitaine seulement).
#
# Usage dans un modèle :
#   include Sluggable
#   def slug_source = title   # champ texte servant de base au slug
#
# Résolution en controller :
#   Match.from_param(params[:id])   # accepte le slug OU un ancien id numérique
#
# to_param renvoie le slug → tous les path helpers (match_path(@match), etc.)
# émettent automatiquement le slug, sans autre modification des vues.
module Sluggable
  extend ActiveSupport::Concern

  # Longueur du suffixe aléatoire (base36 : minuscules + chiffres).
  SLUG_SUFFIX_LENGTH = 6
  # Longueur max de la partie lisible, pour éviter des URLs à rallonge.
  SLUG_BASE_MAX_LENGTH = 60

  included do
    before_validation :generate_slug, on: :create
    validates :slug, presence: true, uniqueness: true
  end

  class_methods do
    # Résout un enregistrement à partir d'un paramètre d'URL.
    # Tente d'abord le slug, puis retombe sur l'id numérique pour ne pas casser
    # les anciens liens / favoris en /matches/42. Lève RecordNotFound si rien.
    def from_param(param)
      find_by(slug: param) || find(param)
    end

    # Variante NILABLE de from_param : renvoie nil au lieu de lever si rien ne
    # correspond. À utiliser quand l'appelant gère explicitement l'absence
    # (ex: chat sticky data-turbo-permanent qui peut pointer un record supprimé).
    def find_by_param(param)
      find_by(slug: param) || find_by(id: param)
    end
  end

  # Utilisé par Rails pour générer les URLs (match_path, url_for, etc.).
  def to_param
    slug
  end

  private

  # Génère un slug unique : "<base-lisible>-<suffixe>".
  def generate_slug
    return if slug.present?

    base = slug_source.to_s.parameterize.first(SLUG_BASE_MAX_LENGTH)
    base = self.class.name.downcase if base.blank?

    loop do
      candidate = "#{base}-#{SecureRandom.alphanumeric(SLUG_SUFFIX_LENGTH).downcase}"
      break(self.slug = candidate) unless self.class.exists?(slug: candidate)
    end
  end
end
