# Format « Critérium Fédéral » (FFTT) : barrages, consolante et matchs de classement.
#
# ── Pourquoi la colonne `branch` ────────────────────────────────────────────────
# Jusqu'ici une ronde était identifiée par (tournoi, phase, numéro) — un index
# unique qui suppose qu'une phase ne contient qu'UNE suite de tours. Le Critérium
# casse cette hypothèse : le match pour la 3e place et le mini-tableau des places
# 5 à 8 se jouent EN PARALLÈLE, tous deux en phase "classification", tous deux au
# tour n°1. `branch` ajoute la seconde dimension manquante.
#
# Convention : "main", ou un token "<table>:<première place>-<dernière place>"
# (ex. "ok:5-8", "ko:19-20"). Cf. CriteriumStructure, qui produit ces tokens.
#
# `null: false, default: "main"` est IMPÉRATIF, pas cosmétique : dans un index
# unique PostgreSQL, NULL est distinct de NULL. Une colonne nullable autoriserait
# donc des doublons (tournoi, "bracket", NULL, 1) et ferait perdre la garde
# anti-double-clic que cet index assure aujourd'hui (cf. PoolBuilder#next_round!).
# Le défaut backfill aussi les rondes existantes → aucun tournoi en cours cassé.
class AddCriteriumFederal < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_rounds, :branch, :string, null: false, default: "main"

    remove_index :tournament_rounds, column: %i[tournament_id phase number], unique: true,
                 name: "index_tournament_rounds_on_tournament_id_and_phase_and_number"
    add_index :tournament_rounds, %i[tournament_id phase branch number], unique: true,
              name: "index_tournament_rounds_on_tid_phase_branch_number"

    # Constitution des poules : NULL = "random", le tirage au sort intégral
    # d'aujourd'hui. "pots" active les chapeaux (cf. PoolSeeding).
    add_column :tournaments, :pool_seeding_mode, :string
    # Nombre de chapeaux NUMÉROTÉS (chacun de la taille du nombre de poules) ;
    # le reste des joueurs forme le « chapeau général ». NULL = 2.
    add_column :tournaments, :seeded_pot_count, :integer
    # "criterium" (barrages + tableau OK + consolante) ou "integral" (tableau
    # unique à classement intégral, effectif réduit). NULL = déduit de l'effectif.
    add_column :tournaments, :final_phase_mode, :string

    # Chapeau du joueur. NULL = chapeau général (niveau inconnu, tirage libre).
    add_column :tournament_users, :pot, :integer
  end
end
