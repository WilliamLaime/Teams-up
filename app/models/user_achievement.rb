class UserAchievement < ApplicationRecord
  # Appartient à un utilisateur
  belongs_to :user
  # Appartient à un achievement
  belongs_to :achievement

  # Un utilisateur ne peut débloquer le même achievement qu'une seule fois
  validates :user_id, uniqueness: { scope: :achievement_id }
end
