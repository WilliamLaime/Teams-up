# État de lecture du chat d'un match de tournoi, par utilisateur.
#
# Sert la pastille « non-lu » posée sur la bulle de discussion de la carte. Le chat
# n'apparaissant nulle part ailleurs (pas d'entrée dans la sidebar globale des
# conversations, c'est voulu), cette pastille est le SEUL signal qu'un message
# attend — sans elle, un joueur peut ne jamais savoir que son adversaire a écrit.
#
# ── Pourquoi une table dédiée ───────────────────────────────────────────────────
# Les autres chats posent leur `last_read_at` sur la table de jointure existante
# (match_users.last_read_at, team_members.chat_last_read_at). Ici il n'y en a pas
# d'utilisable : un joueur a UNE ligne tournament_users pour tout le tournoi, mais
# JOUE PLUSIEURS matchs — l'état de lecture est par (match, utilisateur), pas par
# (tournoi, utilisateur).
#
# La ligne est créée à la première ouverture du chat, jamais à l'inscription :
# l'absence de ligne signifie « n'a rien lu », ce que la requête de la pastille
# traite comme une date infiniment ancienne.
class CreateTournamentMatchChatReads < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_match_chat_reads do |t|
      t.references :tournament_match, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_read_at, null: false

      t.timestamps
    end

    # Une seule ligne par (match, utilisateur) : l'upsert à l'ouverture du chat
    # s'appuie sur cette contrainte pour rester atomique sous concurrence (deux
    # onglets ouverts sur le même match).
    add_index :tournament_match_chat_reads, [:tournament_match_id, :user_id],
              unique: true, name: "index_tmatch_chat_reads_on_tmatch_and_user"
  end
end
