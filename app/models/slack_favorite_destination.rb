# Destination Slack (channel ou message direct) épinglée en favori par une identité.
# Voir db/migrate/*_create_slack_favorite_destinations.rb pour le détail des colonnes.
# Les favoris remontent en tête du sélecteur de partage (groupe « ★ Favoris »).
class SlackFavoriteDestination < ApplicationRecord
  belongs_to :slack_identity

  validates :channel_id, presence: true,
                         uniqueness: { scope: :slack_identity_id }
  validates :channel_name, presence: true
end
