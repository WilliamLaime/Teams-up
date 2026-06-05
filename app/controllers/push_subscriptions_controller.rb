# Gère l'enregistrement et la suppression des subscriptions Web Push.
# Appelé par le Stimulus controller `push_notification_controller.js` côté navigateur.
class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  # Ce controller ne gère pas de ressources métier soumises à Pundit :
  # les subscriptions appartiennent toujours à current_user (pas d'accès cross-user).
  # On skip les after_actions Pundit pour éviter une PunditAuthorizationNotPerformedError
  # (même pattern que VenuesController et SportsController).
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # POST /push_subscriptions
  # Reçoit une subscription JSON du navigateur et la persiste en base.
  # Utilise find_or_create_by pour gérer les doublons (même endpoint = même appareil).
  def create
    subscription = current_user.push_subscriptions.find_or_initialize_by(
      endpoint: subscription_params[:endpoint]
    )
    subscription.assign_attributes(
      p256dh: subscription_params[:p256dh],
      auth:   subscription_params[:auth]
    )

    if subscription.save
      render json: { status: "ok" }, status: :ok
    else
      render json: { error: subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /push_subscriptions
  # Supprime la subscription correspondant à l'endpoint fourni (désabonnement).
  def destroy
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint])&.destroy
    head :no_content
  end

  private

  def subscription_params
    params.require(:subscription).permit(:endpoint, :p256dh, :auth)
  end
end
