# Représente un établissement sportif en France
# Les données proviennent du fichier CSV importé via la rake task db:import_venues
class Venue < ApplicationRecord
  # Un lieu peut être associé à plusieurs matchs
  has_many :matches

  # Validation : le nom et la ville sont obligatoires
  validates :name, presence: true
  validates :city, presence: true

  # Scope : filtrer par ville (insensible à la casse)
  scope :in_city, ->(city) { where("city ILIKE ?", "%#{city}%") }

  # Scope : filtrer par type de sport (insensible à la casse)
  scope :by_sport, ->(sport) { where("sport_type ILIKE ?", "%#{sport}%") }
end
