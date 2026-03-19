class Profil < ApplicationRecord
  belongs_to :user

  # Prénom et nom sont obligatoires
  validates :first_name, presence: { message: "Le prénom est obligatoire" }
  validates :last_name, presence: { message: "Le nom est obligatoire" }

  # Active Storage — permet d'attacher une photo de profil
  # La photo est stockée sur Cloudinary (configuré dans config/storage.yml)
  has_one_attached :avatar

  # Niveau et rôle par sport — un enregistrement par sport pratiqué
  has_many :sport_profils, dependent: :destroy
end
