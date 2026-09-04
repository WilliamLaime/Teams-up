# Chat d'organisation attaché à un match de tournoi.
#
# ── Le besoin ───────────────────────────────────────────────────────────────────
# Deux joueurs tirés l'un contre l'autre doivent convenir d'une date. Jusqu'ici le
# seul moyen était d'aller sur le profil de l'adversaire et d'ouvrir un message
# privé — un détour que personne ne fait.
#
# ── Pourquoi pas le chat de la rencontre (Match) ────────────────────────────────
# Un TournamentMatch peut avoir un Match rattaché (has_one :match), qui possède
# déjà un chat complet. Mais ce Match n'existe qu'une fois la date fixée, alors que
# le chat sert précisément à la fixer : le chat serait arrivé après le besoin.
# Et son ConversationPolicy autorise les match_users, pas les organisateurs du
# tournoi, qui doivent pouvoir arbitrer.
#
# ── Pourquoi une 4e clé étrangère sur messages ──────────────────────────────────
# C'est le pattern déjà en place ici : `messages` porte match_id,
# private_conversation_id et team_id, tous nullables, et Message valide qu'au moins
# un soit présent. `team_id` a été ajouté exactement de cette façon. Une table de
# messages séparée aurait dupliqué le partial de rendu, les broadcasts et le
# controller pour aucun gain.
#
# L'index composé (tournament_match_id, created_at) reproduit celui des trois
# autres contextes : le fil se lit toujours trié par date sur un seul match.
class AddTournamentMatchToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :tournament_match, foreign_key: true, null: true
    add_index :messages, [:tournament_match_id, :created_at],
              name: "index_messages_on_tournament_match_id_created_at"
  end
end
