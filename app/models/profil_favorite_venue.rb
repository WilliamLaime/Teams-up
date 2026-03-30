class ProfilFavoriteVenue < ApplicationRecord
  # Associations : cette table lie un Profil à un Venue
  belongs_to :profil
  belongs_to :venue

  # Validation : empêche les doublons
  # Un profil ne peut pas ajouter 2x le même lieu en favori
  validates :profil_id, uniqueness: { scope: :venue_id }
end
