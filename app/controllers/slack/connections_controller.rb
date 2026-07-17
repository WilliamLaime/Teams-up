# Flux B — Liaison de l'identité Slack d'un utilisateur à son compte Teams-up.
#
# Contrairement à la connexion Google (qui matche/crée un compte par email), il ne
# s'agit PAS d'un login : l'utilisateur est DÉJÀ connecté et veut RELIER son identité
# Slack au compte courant. On utilise "Se connecter avec Slack" (OpenID Connect) et on
# vérifie que le retour correspond bien à `current_user` (state signé) — jamais de
# rapprochement par email.
module Slack
  class ConnectionsController < ApplicationController
    STATE_PURPOSE = :slack_link

    # GET /slack/connect → redirige vers l'écran "Se connecter avec Slack".
    def connect
      skip_authorization
      redirect_to authorize_url, allow_other_host: true
    end

    # GET /slack/connect/callback → récupère l'identité et la relie au compte courant.
    def callback
      skip_authorization
      return redirect_with_error unless valid_state? && params[:code].present?

      claims = fetch_identity_claims
      workspace = SlackWorkspace.find_by(team_id: claims[:team_id])

      # Le workspace doit d'abord avoir installé l'app (flux A) — sinon aucun bot_token
      # pour poster, et pas de rattachement possible.
      unless workspace
        return redirect_to profil_integrations_path,
                           alert: "Cet espace Slack n'a pas encore installé Teams-up. Demande à un admin de l'installer."
      end

      link_identity(workspace, claims)
    rescue Slack::ApiClient::Error => e
      Rails.logger.error("[Slack connect] #{e.slack_error}")
      redirect_to profil_integrations_path,
                  alert: "La liaison Slack a échoué. Réessaie dans quelques instants."
    end

    # DELETE /slack/disconnect/:id → délie une identité Slack du compte courant.
    def destroy
      identity = current_user.slack_identities.find(params[:id])
      skip_authorization
      identity.destroy
      redirect_to profil_integrations_path, notice: "Compte Slack délié."
    end

    private

    def authorize_url
      query = {
        response_type: "code",
        client_id: Slack.client_id,
        scope: Slack::OPENID_SCOPES.join(" "),
        redirect_uri: slack_connect_callback_url,
        state: signed_state
      }
      "#{Slack::OPENID_AUTHORIZE_URL}?#{query.to_query}"
    end

    def signed_state
      Rails.application.message_verifier(STATE_PURPOSE)
           .generate(current_user.id, expires_in: 15.minutes)
    end

    # Le state doit correspondre à l'utilisateur courant : protège contre le login-CSRF
    # (quelqu'un tenterait de relier SON Slack au compte d'une victime).
    def valid_state?
      user_id = Rails.application.message_verifier(STATE_PURPOSE).verify(params[:state])
      user_id == current_user.id
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end

    # Échange le code contre un id_token OpenID et en extrait les claims utiles
    # (slack_user_id = `sub`, team_id, team_name).
    def fetch_identity_claims
      data = Slack::ApiClient.post_form(Slack::OPENID_TOKEN_URL,
                                        client_id: Slack.client_id,
                                        client_secret: Slack.client_secret,
                                        code: params[:code],
                                        grant_type: "authorization_code",
                                        redirect_uri: slack_connect_callback_url)
      payload = decode_id_token(data["id_token"])
      {
        slack_user_id: payload["sub"],
        team_id: payload["https://slack.com/team_id"],
        team_name: payload["https://slack.com/team_name"]
      }
    end

    # Décode la charge utile (payload) d'un JWT id_token sans vérifier la signature :
    # le jeton vient d'être obtenu directement du endpoint de token Slack via TLS
    # (canal déjà authentifié), il n'a pas transité par le navigateur.
    def decode_id_token(id_token)
      payload_segment = id_token.split(".")[1]
      JSON.parse(Base64.urlsafe_decode64(add_padding(payload_segment)))
    end

    # Base64 URL-safe sans padding → on rétablit le padding "=" attendu par le décodeur.
    def add_padding(segment)
      segment + "=" * ((4 - segment.length % 4) % 4)
    end

    def link_identity(workspace, claims)
      identity = SlackIdentity.find_or_initialize_by(
        slack_workspace: workspace,
        slack_user_id: claims[:slack_user_id]
      )

      # Une identité Slack ne peut être rattachée qu'à un seul compte Teams-up.
      if identity.persisted? && identity.user_id != current_user.id
        return redirect_to profil_integrations_path,
                           alert: "Ce compte Slack est déjà lié à un autre utilisateur Teams-up."
      end

      identity.update!(user: current_user, slack_team_id: workspace.team_id)
      redirect_to profil_integrations_path,
                  notice: "Ton compte Slack est lié à « #{workspace.team_name} » ✅"
    end

    def redirect_with_error
      redirect_to profil_integrations_path,
                  alert: "Liaison Slack annulée ou lien expiré. Réessaie."
    end
  end
end
