# Flux A — Installation de l'app Teams-up dans un workspace Slack.
#
# C'est une action d'admin : un utilisateur connecté clique "Installer sur Slack",
# est redirigé vers l'écran d'autorisation Slack, choisit son workspace, puis Slack
# nous renvoie un `code` qu'on échange contre le jeton de bot (bot_token).
#
# Ce controller vit côté navigateur (session Devise présente) → il hérite
# d'ApplicationController pour bénéficier de authenticate_user!. On désactive Pundit
# au cas par cas via skip_authorization (pages personnelles, aucun record à autoriser).
module Slack
  class OauthController < ApplicationController
    # Le `state` est signé pour empêcher un tiers de forger le retour OAuth (CSRF).
    # On y embarque l'id de l'utilisateur qui a lancé l'installation, avec expiration.
    STATE_PURPOSE = :slack_install

    # GET /slack/install → redirige vers l'écran d'autorisation du bot.
    def install
      skip_authorization
      redirect_to authorize_url, allow_other_host: true
    end

    # GET /slack/oauth/callback → échange le code contre le jeton de bot.
    def callback
      skip_authorization
      return redirect_with_error unless valid_state? && params[:code].present?

      data = Slack::ApiClient.post_form(Slack::OAUTH_ACCESS_URL,
                                        client_id: Slack.client_id,
                                        client_secret: Slack.client_secret,
                                        code: params[:code],
                                        redirect_uri: slack_oauth_callback_url)

      workspace = upsert_workspace(data)
      link_installer_identity(workspace, data)

      redirect_to profil_integrations_path,
                  notice: "Teams-up est installé sur l'espace Slack « #{workspace.team_name} » 🎉"
    rescue Slack::ApiClient::Error => e
      Rails.logger.error("[Slack install] #{e.slack_error}")
      redirect_to profil_integrations_path,
                  alert: "L'installation Slack a échoué. Réessaie dans quelques instants."
    end

    private

    # Construit l'URL d'autorisation OAuth du bot avec les scopes et le state signé.
    # `team` (optionnel) force le workspace ciblé : sans lui, Slack sélectionne
    # d'office le workspace "le plus actif" de la session, qui n'est pas forcément
    # celui qu'on veut installer. On le passe via /slack/install?team=T0123ABC.
    def authorize_url
      query = {
        client_id: Slack.client_id,
        scope: Slack::BOT_SCOPES.join(","),
        redirect_uri: slack_oauth_callback_url,
        state: signed_state
      }
      query[:team] = params[:team] if params[:team].present?
      "#{Slack::OAUTH_AUTHORIZE_URL}?#{query.to_query}"
    end

    def signed_state
      Rails.application.message_verifier(STATE_PURPOSE)
           .generate(current_user.id, expires_in: 15.minutes)
    end

    # Vérifie que le state nous appartient et correspond à l'utilisateur courant.
    def valid_state?
      user_id = Rails.application.message_verifier(STATE_PURPOSE).verify(params[:state])
      user_id == current_user.id
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end

    # Crée ou met à jour le workspace à partir de la réponse oauth.v2.access.
    def upsert_workspace(data)
      workspace = SlackWorkspace.find_or_initialize_by(team_id: data.dig("team", "id"))
      workspace.update!(
        team_name: data.dig("team", "name"),
        bot_token: data["access_token"], # jeton "xoxb-..." (chiffré au repos)
        bot_user_id: data["bot_user_id"],
        scope: data["scope"],
        installer_user: current_user
      )
      workspace
    end

    # Lie automatiquement l'installateur : il a autorisé l'app, on connaît son slack_user_id.
    def link_installer_identity(workspace, data)
      slack_user_id = data.dig("authed_user", "id")
      return if slack_user_id.blank?

      identity = SlackIdentity.find_or_initialize_by(slack_workspace: workspace, slack_user_id:)
      # Ne pas voler une identité déjà rattachée à un autre compte Teams-up.
      return if identity.persisted? && identity.user_id != current_user.id

      identity.update!(user: current_user, slack_team_id: workspace.team_id)
    end

    def redirect_with_error
      redirect_to profil_integrations_path,
                  alert: "Installation Slack annulée ou lien expiré. Réessaie."
    end
  end
end
