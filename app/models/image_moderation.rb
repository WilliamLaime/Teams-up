# Résultat de la modération IA d'une image utilisateur.
#
# Une ligne par couple (record modérable, nom d'attachement) :
#   - Profil  + "avatar"
#   - Team    + "badge_image"
#   - Team    + "cover_image"
#
# Le modèle est polymorphique pour éviter de dupliquer la logique et la table
# d'admin pour chaque type. La création/mise à jour des lignes est orchestrée
# par `ImageModeration::Checker`, jamais directement depuis les vues.
class ImageModeration < ApplicationRecord
  # ── Exceptions ─────────────────────────────────────────────────────────────
  # Hiérarchie des erreurs levées par les adapters et le Checker.
  # `Error` est la classe racine : un `rescue ImageModeration::Error` dans le
  # Job attrape toutes les erreurs du module en une seule clause.
  #
  # Distinction importante pour le comportement du Job :
  #   - RateLimitError    → retry avec backoff (transitoire, 429)
  #   - ApiError          → retry avec backoff (transitoire, 5xx/timeout)
  #   - QuotaExceededError→ PAS de retry (quota mensuel = erreur durable jusqu'à
  #                         la fin du mois, retryer consomme des jobs pour rien)
  class Error < StandardError; end
  class ApiError < Error; end
  class RateLimitError < ApiError; end
  class QuotaExceededError < Error; end

  # ── Associations ───────────────────────────────────────────────────────────
  # Polymorphique : pointe soit vers un Profil, soit vers un Team.
  # `optional: false` (défaut Rails 8) garantit qu'une modération est toujours
  # rattachée à un record existant.
  belongs_to :moderatable, polymorphic: true

  # ── Statuts ────────────────────────────────────────────────────────────────
  # Enum stocké en string pour lisibilité (pas d'integer opaque en base).
  # `prefix: true` évite les collisions de méthodes : on utilise
  # `moderation.status_rejected?` plutôt que `moderation.rejected?` qui
  # pourrait entrer en conflit avec d'autres concerns plus tard.
  enum :status, {
    pending: "pending", # Job enfilé, pas encore traité
    approved: "approved",  # Score < seuil, image OK
    rejected: "rejected",  # Score >= seuil, image purgée
    errored: "errored" # Erreur API / quota dépassé (fail-open : image visible)
  }, prefix: true

  # ── Scopes ─────────────────────────────────────────────────────────────────
  # Lignes modérées pendant le mois en cours. Alimente le compteur de quota
  # Sightengine free tier (2000 ops/mois) affiché dans le dashboard admin,
  # ainsi que l'alerte 80% qui se déclenche à 1600 lignes.
  scope :this_month, lambda {
    where(checked_at: Time.current.beginning_of_month..Time.current.end_of_month)
  }

  # Lignes rejetées sur les dernières 24h — utilisé par le widget stats admin.
  scope :rejected_today, -> { status_rejected.where(checked_at: 24.hours.ago..) }

  # Lignes rejetées sur les 7 derniers jours — même usage.
  scope :rejected_this_week, -> { status_rejected.where(checked_at: 7.days.ago..) }

  # ── Validations ────────────────────────────────────────────────────────────
  # Une seule ligne par couple (record, attachement). L'index DB est déjà unique,
  # cette validation côté modèle donne un message d'erreur propre côté Rails
  # avant que la contrainte DB ne renvoie une ActiveRecord::RecordNotUnique.
  validates :attachment_name,
            presence: true,
            uniqueness: { scope: %i[moderatable_type moderatable_id] }

  validates :provider, presence: true

  # Le score est optionnel (nil tant qu'on n'a pas d'appel API réussi), mais
  # s'il est présent il doit être dans [0, 1] comme toute probabilité.
  validates :score,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            allow_nil: true

  # ── Constantes ─────────────────────────────────────────────────────────────
  # Seuil au-dessus duquel une image est automatiquement rejetée. Décidé dans
  # tasks/todo.md : 0.8 offre un bon compromis entre rappel (on attrape la
  # majorité des NSFW) et précision (peu de faux positifs sur photos sportives).
  NSFW_THRESHOLD = 0.8

  # Quota mensuel du free tier Sightengine. Au-delà, l'adapter lève
  # QuotaExceededError et le Checker passe en statut errored (fail-open).
  MONTHLY_QUOTA = 2000

  # Pourcentage du quota à partir duquel on alerte l'admin (80% → 1600 ops).
  # Ça laisse une marge de 20% pour migrer d'adapter ou upgrade sans panne.
  QUOTA_ALERT_RATIO = 0.8

  # ── Méthodes de classe ─────────────────────────────────────────────────────

  # Nombre d'ops consommées sur le quota mensuel Sightengine. Seules les lignes
  # avec un `checked_at` comptent (pending = pas d'appel API = pas d'op).
  def self.quota_used_this_month
    this_month.where.not(checked_at: nil).count
  end

  # Vrai si on a dépassé le seuil d'alerte (par défaut 80% du quota). Utilisé
  # par le widget admin et par le Checker pour déclencher l'alerte admin.
  def self.quota_alert?
    quota_used_this_month >= (MONTHLY_QUOTA * QUOTA_ALERT_RATIO)
  end
end
