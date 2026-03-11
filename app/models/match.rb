class Match < ApplicationRecord
  # Le créateur du match (organisateur)
  belongs_to :user, optional: true
  has_many :match_users, dependent: :destroy
  has_many :users, through: :match_users

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
