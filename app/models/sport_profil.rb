class SportProfil < ApplicationRecord
  # Appartient au profil de l'utilisateur
  belongs_to :profil
  # Appartient à un sport
  belongs_to :sport

  # Valeurs autorisées pour le niveau
  LEVELS = ["Débutant", "Intermédiaire", "Avancé"].freeze
end
