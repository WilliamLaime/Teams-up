class CreateChatEmailDigests < ActiveRecord::Migration[8.1]
  # Mémorise, pour chaque (destinataire, conversation), la « fenêtre » de
  # regroupement des notifications de chat.
  #
  # Pourquoi une table : un joueur qui écrit une phrase en 3 lignes enverrait
  # 3 mails. On veut UN mail par fenêtre de 3 min et par conversation :
  #   - pending_since : une fenêtre est ouverte (un mail est programmé) — NULL sinon.
  #     Le passage NULL → maintenant se fait en un seul UPDATE conditionnel, ce qui
  #     garantit qu'un seul job est programmé même si deux messages arrivent en
  #     même temps.
  #   - last_sent_at : fin de la dernière fenêtre traitée. Les messages antérieurs
  #     ont déjà été notifiés et ne réapparaissent pas dans le mail suivant.
  #
  # chattable est polymorphe : Match, Team, PrivateConversation ou TournamentMatch
  # (les 4 contextes d'un Message).
  def change
    create_table :chat_email_digests do |t|
      # index: false — couvert par l'index unique ci-dessous, qui commence par user_id
      t.references :user, null: false, foreign_key: true, index: false
      t.references :chattable, polymorphic: true, null: false
      t.datetime :pending_since
      t.datetime :last_sent_at

      t.timestamps
    end

    add_index :chat_email_digests, %i[user_id chattable_type chattable_id],
              unique: true, name: "index_chat_email_digests_on_user_and_chattable"
  end
end
