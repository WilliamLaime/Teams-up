# Traite en arrière-plan un clic « S'inscrire » venu de Slack (bouton Block Kit).
# Découplé du controller pour tenir la fenêtre de 3 s imposée par Slack : l'endpoint
# ACK immédiatement, ce job fait le vrai travail puis répond via `response_url`.
#
# Étapes :
#   1. résoudre l'identité Slack (team_id + user_id) → un compte Teams-up lié ;
#      si non lié → message éphémère invitant à lier son compte (avec le lien) ;
#   2. sinon, inscrire via MatchEnrollmentService (même logique que le web) ;
#   3. renvoyer un message éphémère de confirmation adapté au résultat.
class SlackEnrollJob < ApplicationJob
  queue_as :default

  # L'inscription ne dépend d'aucun objet susceptible de disparaître entre l'enqueue
  # et l'exécution : on gère explicitement le match absent (ci-dessous), pas via discard.

  def perform(match_id:, team_id:, slack_user_id:, response_url:)
    return if response_url.blank?

    identity = SlackIdentity.for_slack(team_id: team_id, user_id: slack_user_id)
    unless identity
      respond(response_url, link_account_text, blocks: link_account_blocks)
      return
    end

    match = Match.find_by(id: match_id)
    return respond(response_url, "Ce match n'existe plus. 🙁") unless match

    result = MatchEnrollmentService.new(match: match, user: identity.user).call
    respond(response_url, message_for(result.status, match))
  end

  private

  # Poste un message éphémère (visible du seul cliqueur) via la response_url.
  # `text` reste le repli obligatoire (notif mobile / accessibilité) même quand
  # on fournit des `blocks` plus riches (ici le bouton « Lier mon compte »).
  def respond(response_url, text, blocks: nil)
    payload = { response_type: "ephemeral", text: text }
    payload[:blocks] = blocks if blocks
    Slack::ApiClient.post_response_url(response_url, payload)
  end

  # Repli texte pour l'invitation à lier son compte.
  def link_account_text
    "Pour t'inscrire depuis Slack, lie d'abord ton compte Teams-up : #{slack_connect_url}"
  end

  # Bloc éphémère : explication + bouton « Lier mon compte à Teams-up » (URL
  # absolue, le job n'a pas de `request`) qui ouvre la page de liaison.
  def link_account_blocks
    [
      { type: "section",
        text: { type: "mrkdwn",
                text: "Pour t'inscrire depuis Slack, lie d'abord ton compte Teams-up. " \
                      "Si tu n'as pas encore de compte, tu pourras en créer un." } },
      { type: "actions",
        elements: [
          { type: "button",
            style: "primary",
            text: { type: "plain_text", text: "Lier mon compte à Teams-up", emoji: true },
            url: slack_connect_url }
        ] }
    ]
  end

  # URL absolue de la page de liaison Slack ↔ Teams-up.
  def slack_connect_url
    Rails.application.routes.url_helpers.slack_connect_url
  end

  # Message de confirmation adapté au résultat de l'inscription.
  def message_for(status, match)
    title = match.title
    case status
    when :approved            then "✅ Tu es inscrit au match « #{title} » !"
    when :waiting             then "⏳ Le match « #{title} » est complet — tu es sur la liste d'attente."
    when :pending             then "📨 Ta demande pour « #{title} » a été envoyée à l'organisateur."
    when :already_registered  then "Tu es déjà inscrit au match « #{title} »."
    when :gender_restricted   then "Le match « #{title} » est réservé aux joueuses."
    else                           "Impossible de t'inscrire pour le moment. Réessaie plus tard."
    end
  end
end
