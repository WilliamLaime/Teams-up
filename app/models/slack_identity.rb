# Lien entre un compte Teams-up et une identité Slack au sein d'un workspace.
# Voir db/migrate/*_create_slack_identities.rb pour le détail des colonnes.
class SlackIdentity < ApplicationRecord
  belongs_to :user
  belongs_to :slack_workspace

  validates :slack_user_id, presence: true, uniqueness: { scope: :slack_workspace_id }
  validates :slack_team_id, presence: true

  # Retrouve l'identité correspondant à une requête entrante Slack (team + user bruts).
  # Renvoie nil si l'utilisateur Slack n'a lié aucun compte Teams-up → l'appelant doit
  # alors refuser l'action (inscription, commande) et inviter à lier son compte.
  def self.for_slack(team_id:, user_id:)
    find_by(slack_team_id: team_id, slack_user_id: user_id)
  end

  # Channel à utiliser par défaut pour cet utilisateur : sa préférence, sinon le repli
  # défini au niveau du workspace.
  def default_channel_id
    preferred_channel_id.presence || slack_workspace.default_channel_id
  end
end
