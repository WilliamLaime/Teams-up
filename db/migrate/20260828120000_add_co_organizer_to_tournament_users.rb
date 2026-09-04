# Double rôle joueur + co-organisateur.
#
# ── Le verrou qu'on lève ────────────────────────────────────────────────────────
# Jusqu'ici `role` portait DEUX informations à la fois : « occupe une place de
# joueur » et « a les droits de gestion ». Combiné à l'index unique
# (tournament_id, user_id), cela rendait les deux mutuellement exclusifs — nommer
# un joueur co-organisateur lui prenait sa place dans le tableau.
#
# ── Pourquoi une colonne et pas une seconde ligne ───────────────────────────────
# Toutes les colonnes de parcours (state, pool, pot, seed, draw_order, wins/losses,
# sets_*, points_*) vivent sur la même ligne que `role`, et TournamentMatch#player_a
# / #player_b pointent une TournamentUser : une seconde ligne pour la même personne
# dupliquerait le classement et rendrait ces clés étrangères ambiguës. On sépare
# donc les deux informations sur la MÊME ligne — `role` reste « occupe une place »,
# `co_organizer` devient « gère le tournoi ».
#
# `null: false, default: false` : la colonne est lue par Tournament#organizer?, qui
# décide de tous les droits de gestion. Un NULL y serait falsy, donc silencieusement
# correct, mais un défaut explicite évite d'avoir à s'en remettre à ce hasard.
class AddCoOrganizerToTournamentUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_users, :co_organizer, :boolean, null: false, default: false

    # Rattrapage des co-organisateurs existants : l'information était dans `role`,
    # elle passe dans la colonne. Leur `role` est laissé tel quel — ils continuent
    # de ne PAS occuper de place de joueur, ce qui reste le bon comportement pour
    # quelqu'un qui n'a jamais rejoint le tournoi.
    up_only do
      execute "UPDATE tournament_users SET co_organizer = TRUE WHERE role = 'co_organisateur'"
    end
  end
end
