# Traite en arrière-plan un clic « Se désinscrire » venu de Slack (bouton Block Kit).
# Pendant de SlackEnrollJob. Découplé du controller pour tenir la fenêtre de 3 s
# imposée par Slack : l'endpoint ACK immédiatement, ce job fait le vrai travail
# puis répond via `response_url`.
#
# Étapes :
#   1. résoudre l'identité Slack (team_id + user_id) → un compte Teams-up lié ;
#      si non lié → message éphémère invitant à lier son compte ;
#   2. sinon, désinscrire via MatchUnenrollmentService (même logique que le web :
#      promotion de la file d'attente, destruction, email à l'organisateur) ;
#   3. renvoyer un message éphémère de confirmation adapté au résultat.
#
# La carte du match se met à jour toute seule : le destroy déclenche le callback
# MatchUser#refresh_slack_cards qui ré-édite la liste des inscrits.
class SlackUnenrollJob < ApplicationJob
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

    result = MatchUnenrollmentService.new(match: match, user: identity.user).call
    respond(response_url, message_for(result.status, match))
  end

  private

  # Message de confirmation adapté au résultat de la désinscription.
  def message_for(status, match)
    title = match.title
    case status
    when :left            then "👋 Tu t'es désinscrit du match « #{title} »."
    when :not_registered  then "Tu n'étais pas inscrit au match « #{title} »."
    else                       "Impossible de te désinscrire pour le moment. Réessaie plus tard."
    end
  end
end
