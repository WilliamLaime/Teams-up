class AddRequestedPoolCountToTournaments < ActiveRecord::Migration[8.1]
  # Nombre de poules VOULU par l'organisation, choisi dans la modale de lancement
  # une fois l'effectif réel connu. NULL = « non fixé », comme les autres réglages
  # de structure (players_per_pool, bracket_size…).
  #
  # Pourquoi une colonne de plus alors que `players_per_pool` existe déjà : une
  # TAILLE ne sait pas exprimer tous les découpages. Le nombre de poules s'en
  # déduit par ⌈effectif / taille⌉, et certains découpages n'ont aucune taille qui
  # les produise — 25 joueurs en 8 poules de 3 ou 4 (⌈25/4⌉ = 7, ⌈25/3⌉ = 9) est
  # pourtant un découpage réglementaire du Critérium Fédéral. Le nombre de poules,
  # lui, décrit n'importe quel découpage équilibré sans ambiguïté.
  def change
    add_column :tournaments, :requested_pool_count, :integer
  end
end
