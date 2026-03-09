class Profil < ApplicationRecord
  belongs_to :user

  # Active Storage — permet d'attacher une photo de profil
  # La photo est stockée sur Cloudinary (configuré dans config/storage.yml)
  has_one_attached :avatar
end
