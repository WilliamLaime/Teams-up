# Trace d'une carte de match postée dans un channel Slack (channel + ts du message).
# Permet de ré-éditer la carte (chat.update) aux transitions de statut du match
# (À venir → En cours → Terminé) — voir SlackMatchStatusJob.
# Voir db/migrate/*_create_slack_match_messages.rb pour le détail des colonnes.
class SlackMatchMessage < ApplicationRecord
  belongs_to :match
  belongs_to :slack_workspace

  validates :channel_id, presence: true
  validates :message_ts, presence: true, uniqueness: { scope: :channel_id }

  # Enregistre (ou met à jour) le message suivi pour un couple (match, channel).
  # Le re-partage dans le même channel écrase l'ancien ts plutôt que d'empiler.
  def self.track!(match:, slack_workspace:, channel_id:, message_ts:)
    find_or_initialize_by(match_id: match.id, channel_id: channel_id).update!(
      slack_workspace: slack_workspace,
      message_ts: message_ts
    )
  end
end
