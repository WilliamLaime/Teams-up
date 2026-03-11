class Match < ApplicationRecord
  # Permet la recherche full-text avec pg_search
  include PgSearch::Model

  # Scope de recherche : cherche dans title, place, description du match
  # et dans l'email de l'utilisateur créateur (via la relation belongs_to :user)
  # prefix: true → trouve aussi les mots partiels (ex: "Pari" trouve "Paris")
  pg_search_scope :search_by_title_place_and_creator,
    against: [:title, :place, :description],
    associated_against: {
      profil: [:first_name, :last_name]  # Cherche aussi par prénom/nom du créateur via user → profil
    },
    using: { tsearch: { prefix: true } }

  # Le créateur du match (organisateur)
  belongs_to :user, optional: true
  has_many :match_users, dependent: :destroy
  has_many :users, through: :match_users

  # Accès direct au profil du créateur (via user) — utilisé par pg_search
  has_one :profil, through: :user

  # ── ActionCable : mises à jour en temps réel ─────────────────────────────
  # Diffuse automatiquement sur le canal "matches" :
  #   - création  → ajoute la carte en bas de la liste (append)
  #   - mise à jour → remplace la carte existante (replace)
  #   - suppression → retire la carte de la page (remove)
  # La vue s'abonne avec <%= turbo_stream_from "matches" %>
  broadcasts_to ->(match) { "matches" }

  # Modes de validation disponibles pour l'organisateur
  VALIDATION_MODES = ["automatic", "manual"].freeze

  # Niveaux disponibles (freeze = tableau immuable, bonne pratique Ruby)
  LEVELS = ["Tout niveau", "Débutant", "Intermédiaire", "Avancé"].freeze

  # Validation : le niveau est obligatoire
  validates :level, presence: true, inclusion: { in: LEVELS }

  # Validation : le match doit être prévu au minimum 30 minutes à l'avance
  validate :match_must_be_at_least_30min_in_future, on: [:create, :update]

  # Retourne vrai si le match est en mode validation manuelle
  def manual_validation?
    validation_mode == "manual"
  end

  # Retourne l'inscription de l'organisateur du match
  def organizer_match_user
    match_users.find_by(role: "organisateur")
  end

  # Retourne vrai si le match est complet (plus de places disponibles)
  def full?
    player_left.to_i <= 0
  end

  # Retourne vrai si le match a lieu dans moins de 2 heures (et n'est pas encore passé)
  def urgent?
    return false unless date.present? && time.present?
    dt = build_datetime
    dt > Time.current && dt <= Time.current + 2.hours
  end

  # Retourne vrai si le match est déjà passé (date+heure dépassées)
  def past?
    return false unless date.present? && time.present?
    build_datetime < Time.current
  end

  private

  # Construit un DateTime combinant les champs date et time du match
  def build_datetime
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, 0)
  end

  # Vérifie que le match est prévu au moins 30 min dans le futur
  def match_must_be_at_least_30min_in_future
    return unless date.present? && time.present?
    if build_datetime < Time.current + 30.minutes
      errors.add(:base, "Le match doit être prévu au moins 30 minutes à l'avance.")
    end
  end
end
