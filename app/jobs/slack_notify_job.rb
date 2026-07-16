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

    response = notifier.post_message(channel: resolution.channel_id, text: text, blocks: blocks)

    # Pour un match : on mémorise la carte postée puis on planifie sa mise à jour
    # de statut (À venir → En cours → Terminé) via chat.update.
    track_and_schedule_match(record, resolution, response) if record_type == "Match"
  rescue Slack::ApiClient::Error => e
    # Erreur définitive → on log et on abandonne. Erreur transitoire (réseau, rate limit
    # côté Slack) → on relaie pour laisser retry_on réessayer avec backoff.
    raise unless PERMANENT_SLACK_ERRORS.include?(e.slack_error)

    Rails.logger.warn("[SlackNotifyJob] abandon (#{e.slack_error}) pour #{record_type} ##{record_id}")
  end

  private

  # Mémorise la carte Slack (channel + ts) et planifie deux rafraîchissements de
  # statut : au coup d'envoi (→ En cours) et à l'heure de fin (→ Terminé). On ne
  # planifie que les transitions encore à venir (un match déjà commencé/fini est
  # posté directement avec le bon tag par le builder).
  def track_and_schedule_match(match, resolution, response)
    channel_id = response["channel"].presence || resolution.channel_id
    message_ts = response["ts"]
    return if message_ts.blank?

    SlackMatchMessage.track!(
      match:           match,
      slack_workspace: resolution.workspace,
      channel_id:      channel_id,
      message_ts:      message_ts
    )

    SlackMatchStatusJob.schedule_transitions(match)
    SlackMatchPrepJob.schedule(match) # rappel "préparez-vous" à -15 min
  end

  # Réessais avec backoff pour les erreurs transitoires relayées ci-dessus.
  retry_on Slack::ApiClient::Error, wait: :polynomially_longer, attempts: 3
end
