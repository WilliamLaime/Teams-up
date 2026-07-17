# Édite les cartes Slack d'un match ANNULÉ en un avis « 🚫 Match annulé ».
#
# Reçoit des coordonnées de cartes déjà sérialisées (workspace_id, channel_id,
# message_ts) parce que le match — et ses slack_match_messages (cascade) — est
# détruit AVANT l'exécution (cf. MatchCancellationService). On ne peut donc plus
# recharger la carte depuis la base : tout est passé en arguments scalaires.
class SlackMatchCancelJob < ApplicationJob
  queue_as :default

  PERMANENT_SLACK_ERRORS = SlackNotifyJob::PERMANENT_SLACK_ERRORS

  # cards : [{ "workspace_id" =>, "channel_id" =>, "message_ts" => }, ...]
  def perform(match_title, cards)
    builder = Slack::BlockKitBuilder.new
    text    = builder.match_cancelled_text(match_title)
    blocks  = builder.match_cancelled_blocks(match_title)

    Array(cards).each { |card| update_one(card, text, blocks) }
  end

  private

  def update_one(card, text, blocks)
    workspace = SlackWorkspace.find_by(id: card["workspace_id"])
    return unless workspace

    SlackNotifierService.new(workspace).update_message(
      channel: card["channel_id"], ts: card["message_ts"], text: text, blocks: blocks
    )
  rescue Slack::ApiClient::Error => e
    # Carte déjà disparue (supprimée à la main) ou erreur définitive → on log
    # sans réessayer. Erreur transitoire → on relaie pour retry_on.
    if %w[message_not_found cant_update_message channel_not_found].include?(e.slack_error)
      nil
    elsif PERMANENT_SLACK_ERRORS.include?(e.slack_error)
      Rails.logger.warn("[SlackMatchCancelJob] abandon (#{e.slack_error}) carte #{card["channel_id"]}")
    else
      raise
    end
  end

  retry_on Slack::ApiClient::Error, wait: :polynomially_longer, attempts: 3
end
