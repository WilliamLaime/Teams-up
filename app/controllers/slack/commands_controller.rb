# Reçoit les slash commands Slack. Aujourd'hui : `/match`, qui ouvre une modale
# de création de match (Block Kit) via `views.open`.
#
# Slack POST en form-urlencoded (team_id, user_id, channel_id, trigger_id,
# response_url, command, text) et attend une réponse en MOINS DE 3 SECONDES.
# `views.open` DOIT être appelé de façon synchrone : le `trigger_id` n'est valide
# que ~3 s, on ne peut donc pas fiabiliser cet appel dans un job. L'appel réseau
# reste court ; la création réelle du match, elle, se fera à la soumission
# (view_submission, géré par Slack::InteractivityController).
#
# La signature est vérifiée en amont par Slack::BaseController.
module Slack
  class CommandsController < Slack::BaseController
    VIEWS_OPEN_URL = "https://slack.com/api/views.open".freeze

    def create
      return render_ephemeral("Commande inconnue.") unless params[:command] == "/match"

      identity = SlackIdentity.for_slack(team_id: params[:team_id], user_id: params[:user_id])
      return render_ephemeral(link_account_message) unless identity

      open_modal(identity.slack_workspace)
      head :ok
    rescue Slack::ApiClient::Error => e
      # trigger_id expiré, scope manquant… on prévient l'utilisateur sans planter.
      Rails.logger.warn("[Slack::Commands] views.open a échoué (#{e.slack_error})")
      render_ephemeral("Impossible d'ouvrir la fenêtre de création. Réessaie.")
    end

    private

    # Ouvre la modale de création dans le workspace de l'utilisateur.
    def open_modal(workspace)
      view = Slack::MatchModalBuilder.new(
        channel_id:   params[:channel_id],
        response_url: params[:response_url],
        team_id:      params[:team_id]
      ).view

      Slack::ApiClient.post_json(VIEWS_OPEN_URL, workspace.bot_token,
                                 trigger_id: params[:trigger_id], view: view)
    end

    # Réponse éphémère immédiate (visible du seul auteur de la commande).
    def render_ephemeral(text)
      render json: { response_type: "ephemeral", text: text }
    end

    def link_account_message
      url = Rails.application.routes.url_helpers.slack_connect_url
      "Pour créer un match depuis Slack, lie d'abord ton compte Teams-up : #{url}"
    end
  end
end
