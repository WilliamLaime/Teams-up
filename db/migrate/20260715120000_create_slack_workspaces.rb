# Intégration Slack — Lot 1 : fondations.
#
# Un SlackWorkspace représente l'installation de l'app Teams-up dans UN espace de
# travail Slack (un "workspace", ex. l'entreprise Acme). C'est l'admin qui installe
# l'app via le flux OAuth "install" ; en retour Slack nous donne un jeton de bot
# (bot_token, préfixe "xoxb-...") qui autorise Teams-up à poster des messages dans
# ce workspace au nom du bot.
#
# On stocke un workspace par entreprise (multi-workspace) car chaque installation a
# son propre jeton. Le jeton est un SECRET sensible → il est chiffré au repos via
# Active Record Encryption (voir app/models/slack_workspace.rb : `encrypts :bot_token`).
class CreateSlackWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_workspaces do |t|
      # Identifiant unique du workspace côté Slack (ex. "T01ABCDEF").
      # Sert de clé de rapprochement quand Slack nous rappelle (interactivity, events).
      t.string :team_id, null: false
      t.string :team_name

      # Jeton du bot ("xoxb-..."). Chiffré au niveau applicatif → la colonne stocke
      # du texte chiffré, jamais le jeton en clair. `text` car le chiffrement rallonge
      # la valeur au-delà de la taille d'un jeton brut.
      t.text :bot_token

      # ID du bot dans ce workspace (utile pour ignorer nos propres messages en events).
      t.string :bot_user_id

      # Scopes réellement accordés par Slack (audit / debug).
      t.string :scope

      # Channel de repli au niveau workspace si aucun channel n'est précisé ailleurs.
      t.string :default_channel_id
      t.string :default_channel_name

      # Qui a installé l'app (peut être nil si l'installateur n'a pas de compte Teams-up).
      t.references :installer_user, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Un seul enregistrement par workspace Slack.
    add_index :slack_workspaces, :team_id, unique: true
  end
end
