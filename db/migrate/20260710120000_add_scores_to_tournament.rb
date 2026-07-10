# Lot 4 — Scores set-par-set + compteurs de départage.
# On stocke le détail des sets directement sur le match (jsonb) plutôt que dans une
# table enfant : un score est saisi/modifié EN BLOC, jamais requêté isolément, et
# l'agrégation se fait déjà en Ruby (SwissPairing#recompute_stats!).
# Les compteurs sets/points sur l'inscription servent au seeding réel du tableau
# final (set average / point average), comme wins/losses servent aux qualifications.
class AddScoresToTournament < ActiveRecord::Migration[8.1]
  def change
    # Détail set-par-set : tableau de paires [[games_a, games_b], …]. Vide = pas encore saisi.
    add_column :tournament_matches, :sets, :jsonb, null: false, default: []

    # Compteurs de départage (recalculés à chaque ronde depuis les matchs).
    add_column :tournament_users, :sets_won,    :integer, null: false, default: 0
    add_column :tournament_users, :sets_lost,   :integer, null: false, default: 0
    add_column :tournament_users, :points_won,  :integer, null: false, default: 0
    add_column :tournament_users, :points_lost, :integer, null: false, default: 0
  end
end
