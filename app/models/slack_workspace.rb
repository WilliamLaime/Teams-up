# Installation de l'app Teams-up dans un espace de travail Slack.
# Voir db/migrate/*_create_slack_workspaces.rb pour le détail des colonnes.
class SlackWorkspace < ApplicationRecord
  # Chiffrement au repos du jeton de bot : la colonne `bot_token` contient du texte
  # chiffré. Nécessite que les clés Active Record Encryption soient configurées
  # (ACTIVE_RECORD_ENCRYPTION_* en ENV) — sans elles, toute écriture lève une erreur.
  encrypts :bot_token

  # L'utilisateur Teams-up qui a réalisé l'installation (facultatif).
  belongs_to :installer_user, class_name: "User", optional: true

  # Toutes les identités Slack rattachées à ce workspace.
  has_many :slack_identities, dependent: :destroy

  # Cartes de match postées via ce workspace (pour les MAJ de statut).
  has_many :slack_match_messages, dependent: :destroy

  validates :team_id, presence: true, uniqueness: true
end
