# Réponses éphémères Slack partagées par les jobs déclenchés depuis un bouton
# Block Kit d'une carte match (inscription / désinscription). Un job inclut ce
# module pour répondre au cliqueur via sa `response_url` (message visible de lui
# seul), et pour l'inviter à lier son compte quand aucune identité Slack n'est
# rattachée (prérequis pour agir depuis Slack).
module SlackEphemeralResponder
  extend ActiveSupport::Concern

  private

  # Poste un message éphémère (visible du seul cliqueur) via la response_url.
  # `text` reste le repli obligatoire (notif mobile / accessibilité) même quand
  # on fournit des `blocks` plus riches (ex. le bouton « Lier mon compte »).
  def respond(response_url, text, blocks: nil)
    payload = { response_type: "ephemeral", text: text }
    payload[:blocks] = blocks if blocks
    Slack::ApiClient.post_response_url(response_url, payload)
  end

  # Repli texte pour l'invitation à lier son compte.
  def link_account_text
    "Pour agir sur les matchs depuis Slack, lie d'abord ton compte Teams-up : #{slack_connect_url}"
  end

  # Bloc éphémère : explication + bouton « Lier mon compte à Teams-up » (URL
  # absolue, le job n'a pas de `request`) qui ouvre la page de liaison.
  def link_account_blocks
    [
      { type: "section",
        text: { type: "mrkdwn",
                text: "Pour agir sur les matchs depuis Slack, lie d'abord ton compte Teams-up. " \
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
end
