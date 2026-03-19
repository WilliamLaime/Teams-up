class Achievement < ApplicationRecord
  # Un achievement peut être débloqué par plusieurs utilisateurs
  has_many :user_achievements, dependent: :destroy

  # Validations pour garantir la cohérence des données
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }

  # Catégories possibles d'achievements
  CATEGORIES = %w[match social profile].freeze
end
