# Paramètres de structure personnalisables (Lot 7).
#
# Jusqu'ici la structure d'un tournoi était entièrement déduite du format et de
# l'effectif (poules de 4, Final 4/8, 3 victoires pour se qualifier en ronde
# suisse) : l'organisateur voyait un aperçu en LECTURE SEULE. Ces 4 colonnes lui
# permettent de personnaliser chaque critère.
#
# Toutes NULLABLES et NULL par défaut : NULL = « recommandé », c'est-à-dire la
# valeur calculée comme avant (cf. Tournament#pool_size / #final_size /
# #wins_to_qualify / #losses_to_eliminate). Les tournois existants gardent donc
# exactement leur comportement actuel, sans backfill.
#
# Noms de colonnes distincts des méthodes du modèle (players_per_pool vs
# #pool_size, bracket_size vs #final_size…) : les méthodes appliquent le fallback,
# sans jamais masquer un attribut ActiveRecord.
class AddStructureSettingsToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :players_per_pool, :integer
    add_column :tournaments, :bracket_size, :integer
    add_column :tournaments, :swiss_wins_to_qualify, :integer
    add_column :tournaments, :swiss_losses_to_eliminate, :integer
  end
end
