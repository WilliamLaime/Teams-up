# Épinglage/désépinglage d'une destination Slack (channel ou DM) en favori.
#
# Appelé en `fetch` (JSON) depuis le combobox de partage (slack_destination_controller.js),
# donc côté navigateur : on hérite d'ApplicationController pour bénéficier de la session
# Devise et de la protection CSRF. La ressource est strictement personnelle (favoris de
# l'utilisateur courant) → pas de record à autoriser via Pundit (skip_authorization).
#
# Les favoris sont rattachés à la SlackIdentity de l'utilisateur DANS le workspace ciblé :
# on résout donc l'identité via current_user + slack_workspace_id, ce qui garantit qu'on ne
# touche jamais aux favoris d'un autre compte.
module Slack
  class FavoritesController < ApplicationController
    # POST /slack/favorites → épingle { slack_workspace_id, channel_id, channel_name }.
    def create
      skip_authorization
      identity = resolve_identity or return render_not_found
      return render_missing_channel if params[:channel_id].blank?

      favorite = identity.slack_favorite_destinations
                         .find_or_initialize_by(channel_id: params[:channel_id])
      favorite.channel_name = params[:channel_name].presence || params[:channel_id]
      favorite.save!

      render json: { ok: true }
    end

    # DELETE /slack/favorites → désépingle { slack_workspace_id, channel_id }.
    def destroy
      skip_authorization
      identity = resolve_identity or return render_not_found

      identity.slack_favorite_destinations
              .where(channel_id: params[:channel_id]).destroy_all

      render json: { ok: true }
    end

    private

    # L'identité de l'utilisateur courant dans le workspace demandé (nil si absent).
    def resolve_identity
      current_user.slack_identities.find_by(slack_workspace_id: params[:slack_workspace_id])
    end

    def render_not_found
      render json: { ok: false, error: "identity_not_found" }, status: :not_found
    end

    def render_missing_channel
      render json: { ok: false, error: "channel_id_required" }, status: :unprocessable_entity
    end
  end
end
