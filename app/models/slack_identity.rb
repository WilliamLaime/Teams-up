# Lien entre un compte Teams-up et une identité Slack au sein d'un workspace.
# Voir db/migrate/*_create_slack_identities.rb pour le détail des colonnes.
class SlackIdentity < ApplicationRecord
  belongs_to :user
  belongs_to :slack_workspace

  # Destinations épinglées par cet utilisateur (affichées en tête du sélecteur de partage).
  has_many :slack_favorite_destinations, dependent: :destroy

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

  # Favoris au format [libellé, id] — même structure que les groupes Channels/DM du
  # sélecteur, pour un rendu homogène côté JS.
  def favorite_destinations_pairs
    slack_favorite_destinations.order(:channel_name).pluck(:channel_name, :channel_id)
  end
end
