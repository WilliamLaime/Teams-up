# Rafraîchit les cartes Slack d'un match pour refléter son statut courant
# (À venir → En cours → Terminé). Planifié par SlackNotifyJob à l'heure de début
# puis à l'heure de fin du match ; ré-édite chaque message suivi via chat.update.
#
# Idempotent : on reconstruit les blocs au statut du moment, donc un déclenchement
# en retard (worker occupé) reste correct. Un match sans carte suivie → no-op.
class SlackMatchStatusJob < ApplicationJob
  queue_as :default

  # Le match a été supprimé entre-temps → ses SlackMatchMessage le sont aussi
  # (dependent: :destroy), plus rien à mettre à jour.
  discard_on ActiveRecord::RecordNotFound

  PERMANENT_SLACK_ERRORS = SlackNotifyJob::PERMANENT_SLACK_ERRORS

  def perform(match_id)
    match = Match.find(match_id)
    messages = match.slack_match_messages.includes(:slack_workspace)
    return if messages.empty?

    builder = Slack::BlockKitBuilder.new
    text    = builder.match_created_text(match)
    blocks  = builder.match_created_blocks(match)

    messages.each do |msg|
      update_one(msg, text, blocks)
    end
  end

  private

  def update_one(msg, text, blocks)
    SlackNotifierService.new(msg.slack_workspace).update_message(
      channel: msg.channel_id, ts: msg.message_ts, text: text, blocks: blocks
    )
  rescue Slack::ApiClient::Error => e
    # message_not_found / cant_update_message → la carte n'existe plus (supprimée) :
    # on retire la trace pour ne plus réessayer. Autres erreurs définitives → on log.
    if %w[message_not_found cant_update_message channel_not_found].include?(e.slack_error)
      msg.destroy
    elsif PERMANENT_SLACK_ERRORS.include?(e.slack_error)
      Rails.logger.warn("[SlackMatchStatusJob] abandon (#{e.slack_error}) msg ##{msg.id}")
    else
      raise # transitoire → retry_on
    end
  end

  retry_on Slack::ApiClient::Error, wait: :polynomially_longer, attempts: 3
end
