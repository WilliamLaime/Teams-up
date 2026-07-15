# Reçoit les interactions Slack (clics sur les boutons Block Kit).
# Aujourd'hui : le bouton « S'inscrire » (action_id "match_join") posté par
# Slack::BlockKitBuilder#match_created_blocks.
#
# Slack envoie un POST form-urlencoded avec un champ `payload` = JSON, et attend
# une réponse HTTP en MOINS DE 3 SECONDES. On se contente donc d'ACK immédiatement
# (head :ok) et on délègue le vrai travail (résolution d'identité + inscription +
# message de confirmation éphémère) à SlackEnrollJob, qui répondra via `response_url`.
#
# La signature est vérifiée en amont par Slack::BaseController.
module Slack
  class InteractivityController < Slack::BaseController
    def create
      payload = parse_payload
      return head :ok unless payload

      # On ne traite que les clics de bouton pour l'instant.
      return head :ok unless payload["type"] == "block_actions"

      action = Array(payload["actions"]).find { |a| a["action_id"] == "match_join" }
      return head :ok unless action

      SlackEnrollJob.perform_later(
        match_id:      action["value"],
        team_id:       payload.dig("team", "id"),
        slack_user_id: payload.dig("user", "id"),
        response_url:  payload["response_url"]
      )

      head :ok
    end

    private

    # Le payload interactif arrive dans le champ de formulaire `payload` (JSON).
    def parse_payload
      JSON.parse(params[:payload].to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
