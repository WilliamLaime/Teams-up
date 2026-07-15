# Poste une notification Slack pour un match ou un tournoi qui vient d'être créé/partagé.
# Calqué sur MatchWebPushJob : déclenché en background depuis les controllers via
# perform_later, avec réessais sur erreurs transitoires et abandon si l'objet a disparu.
class SlackNotifyJob < ApplicationJob
  queue_as :default

  # Le match/tournoi ou l'utilisateur a été supprimé entre-temps → inutile de réessayer.
  discard_on ActiveRecord::RecordNotFound

  # Erreurs Slack considérées comme DÉFINITIVES : réessayer ne changerait rien.
  PERMANENT_SLACK_ERRORS = %w[
    channel_not_found not_in_channel is_archived invalid_auth
    account_inactive token_revoked missing_scope
  ].freeze

  def perform(record_type, record_id, actor_user_id, channel_id = nil, workspace_id = nil)
    actor = User.find(actor_user_id)

    # Résout workspace + destination à partir de l'organisateur. Rien à faire s'il n'a
    # pas lié Slack (ou pas ce workspace) ou si aucune destination n'est déterminable.
    resolution = Slack::ChannelResolver.for(user: actor, workspace_id: workspace_id, override: channel_id)
    return unless resolution

    record   = record_type.constantize.find(record_id)

    # Match déjà passé → aucune notification (personne ne peut plus s'inscrire).
    return if record.respond_to?(:past?) && record.past?

    builder  = Slack::BlockKitBuilder.new
    notifier = SlackNotifierService.new(resolution.workspace)

    text, blocks =
      case record_type
      when "Match"
        [builder.match_created_text(record), builder.match_created_blocks(record)]
      when "Tournament"
        [builder.tournament_created_text(record), builder.tournament_created_blocks(record)]
      else
        return
      end

    notifier.post_message(channel: resolution.channel_id, text: text, blocks: blocks)
  rescue Slack::ApiClient::Error => e
    # Erreur définitive → on log et on abandonne. Erreur transitoire (réseau, rate limit
    # côté Slack) → on relaie pour laisser retry_on réessayer avec backoff.
    raise unless PERMANENT_SLACK_ERRORS.include?(e.slack_error)

    Rails.logger.warn("[SlackNotifyJob] abandon (#{e.slack_error}) pour #{record_type} ##{record_id}")
  end

  # Réessais avec backoff pour les erreurs transitoires relayées ci-dessus.
  retry_on Slack::ApiClient::Error, wait: :polynomially_longer, attempts: 3
end
