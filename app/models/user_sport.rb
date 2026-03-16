# Modèle UserSport — table de jointure entre User et Sport
# Permet à un utilisateur d'avoir plusieurs sports favoris
class UserSport < ApplicationRecord
  belongs_to :user
  belongs_to :sport

  # Un utilisateur ne peut pas s'inscrire deux fois au même sport
  validates :user_id, uniqueness: { scope: :sport_id }
end
