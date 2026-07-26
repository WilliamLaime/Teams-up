# Intégration Slack — destinations favorites.
#
# Un favori épingle une destination (channel ou message direct) pour une identité Slack
# donnée, afin de la retrouver en tête du sélecteur de partage quand un workspace a
# beaucoup de channels. Rattaché à la SlackIdentity (déjà propre à un workspace) → les
# favoris sont naturellement scoped par workspace, sans colonne supplémentaire.
#
# On stocke `channel_id` (l'id Slack C.../G.../U... transmis tel quel à chat.postMessage)
# ET `channel_name` (le libellé affiché « #general » / « Bob ») : les destinations ne sont
# pas persistées côté Rails (listées à la volée via l'API), donc on garde le libellé pour
# l'afficher sans refaire un appel Slack.
class CreateSlackFavoriteDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_favorite_destinations do |t|
      t.references :slack_identity, null: false, foreign_key: true

      t.string :channel_id,   null: false
      t.string :channel_name, null: false

      t.timestamps
    end

    # Un même channel/DM ne peut être épinglé qu'une fois par identité.
    add_index :slack_favorite_destinations, [:slack_identity_id, :channel_id], unique: true
  end
end
