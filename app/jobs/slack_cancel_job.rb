# Traite en arrière-plan un clic « Annuler le match » venu de Slack (bouton Block
# Kit). Comme SlackEnrollJob / SlackUnenrollJob : l'endpoint ACK en < 3 s, ce job
# fait le travail et répond via `response_url`.
#
# Étapes :
#   1. résoudre l'identité Slack → compte Teams-up lié (sinon : inviter à lier) ;
#   2. n'autoriser QUE l'organisateur du match (record.user) ;
#   3. annuler via MatchCancellationService (suppression + emails + édition des
#      cartes Slack en « Annulé », comme le site) ;
#   4. répondre en éphémère.
class SlackCancelJob < ApplicationJob
  include SlackEphemeralResponder

  queue_as :default

  def perform(match_id:, team_id:, slack_user_id:, response_url:)
    return if response_url.blank?

    identity = SlackIdentity.for_slack(team_id: team_id, user_id: slack_user_id)
    unless identity
      respond(response_url, link_account_text, blocks: link_account_blocks)
      return
    end

    match = Match.find_by(id: match_id)
    return respond(response_url, "Ce match n'existe plus. 🙁") unless match

    # Seul l'organisateur peut annuler.
    unless match.user_id == identity.user_id
      return respond(response_url, "Seul l'organisateur du match peut l'annuler.")
    end

    title = match.title
    MatchCancellationService.new(match: match).call
    respond(response_url, "🚫 Match « #{title} » annulé. Les joueurs inscrits sont prévenus.")
  end
end
