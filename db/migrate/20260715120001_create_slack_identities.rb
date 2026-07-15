# Intégration Slack — Lot 1 : fondations.
#
# Une SlackIdentity relie UN compte Teams-up (user) à UNE identité Slack au sein d'un
# workspace donné. C'est ce qui permet, quand quelqu'un clique "S'inscrire" depuis un
# message Slack, de savoir de quel utilisateur Teams-up il s'agit — et donc de refuser
# l'inscription si le compte n'est pas lié.
#
# On n'ajoute PAS de colonnes Slack sur la table `users` : un même utilisateur peut
# appartenir à plusieurs workspaces (plusieurs entreprises), et on garde `provider`/`uid`
# réservés à la connexion Google. Une identité par (workspace, slack_user_id).
class CreateSlackIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_identities do |t|
      t.references :user,            null: false, foreign_key: true
      t.references :slack_workspace, null: false, foreign_key: true

      # Identifiant de l'utilisateur côté Slack (ex. "U01ABCDEF").
      t.string :slack_user_id, null: false

      # ID du workspace Slack, dénormalisé ici pour un lookup direct lors des requêtes
      # entrantes (interactivity/commands) qui nous envoient team_id + user_id bruts,
      # sans qu'on ait à joindre slack_workspaces.
      t.string :slack_team_id, null: false

      # Channel préféré de CET utilisateur pour poster ses matchs (pré-remplit le
      # formulaire de création et sert de repli au partage manuel).
      t.string :preferred_channel_id
      t.string :preferred_channel_name

      t.timestamps
    end

    # Une identité unique par utilisateur Slack dans un workspace donné.
    add_index :slack_identities, [:slack_workspace_id, :slack_user_id], unique: true
    # Résolution rapide depuis une requête entrante Slack (team + user).
    add_index :slack_identities, [:slack_team_id, :slack_user_id]
  end
end
