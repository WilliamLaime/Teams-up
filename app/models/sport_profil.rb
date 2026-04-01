class SportProfil < ApplicationRecord
  # Appartient au profil de l'utilisateur
  belongs_to :profil
  # Appartient à un sport
  belongs_to :sport

  # Validation : si un niveau est renseigné, il doit appartenir à la grille du sport
  # Le niveau est optionnel sur le profil (l'utilisateur peut ne pas le préciser)
  validate :level_valid_for_sport

  private

  def level_valid_for_sport
    return if level.blank?
    return unless sport.present?

    valid_labels = sport.available_levels.map { |l| l[:label] }
    unless valid_labels.include?(level)
      errors.add(:level, "n'est pas valide pour ce sport (valeurs acceptées : #{valid_labels.join(', ')})")
    end
  end
end
