# ── Accusé de lecture du chat d'un match de tournoi ───────────────────────────
# Une ligne par (match, utilisateur), créée à la PREMIÈRE ouverture du chat :
# l'absence de ligne signifie « n'a jamais rien lu », ce que la requête de la
# pastille traite comme une date infiniment ancienne. Pas de rattrapage à
# l'inscription, donc — un joueur qui n'a jamais ouvert le fil doit justement voir
# la pastille si son adversaire a écrit.
#
# Table dédiée plutôt qu'une colonne sur tournament_users : un joueur a UNE ligne
# d'inscription pour tout le tournoi mais joue PLUSIEURS matchs, l'état de lecture
# est donc par (match, utilisateur).
class TournamentMatchChatRead < ApplicationRecord
  belongs_to :tournament_match
  belongs_to :user

  validates :last_read_at, presence: true
  # Doublon impossible : l'index unique en base porte la même contrainte, ce qui
  # protège aussi de deux onglets ouverts simultanément sur le même match.
  validates :user_id, uniqueness: { scope: :tournament_match_id }

  # ── Marque le fil comme lu pour cet utilisateur ───────────────────────────
  # Appelé à l'ouverture du chat ET à l'envoi d'un message (l'expéditeur vient de
  # lire son propre fil : sans cela, sa pastille se rallumerait sur sa propre carte).
  #
  # upsert plutôt que find_or_initialize + save : deux onglets ouverts sur le même
  # match violeraient l'index unique dans la fenêtre entre le SELECT et l'INSERT.
  # `upsert` court-circuite les validations — c'est assumé, il n'écrit que des
  # valeurs qu'on fournit nous-mêmes ici, jamais des entrées utilisateur.
  def self.mark_read!(tournament_match, user)
    now = Time.current
    upsert(
      {
        tournament_match_id: tournament_match.id,
        user_id: user.id,
        last_read_at: now,
        created_at: now,
        updated_at: now
      },
      unique_by: :index_tmatch_chat_reads_on_tmatch_and_user
    )
  end
end
