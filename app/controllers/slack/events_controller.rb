# Reçoit les événements de l'API Events de Slack (POST JSON).
#
# En v1, Teams-up ne s'abonne à AUCUN event : ce contrôleur existe uniquement pour
# répondre au handshake `url_verification` que Slack envoie lorsqu'on renseigne la
# « Request URL » de l'Events API dans la config de l'app. Slack attend qu'on lui
# renvoie tel quel le `challenge` reçu (< 3 s) pour valider l'URL.
#
# Tout autre type d'event est simplement acquitté (head :ok) sans traitement.
#
# La signature est vérifiée en amont par Slack::BaseController (le challenge est
# lui aussi signé → il passe la vérif HMAC sans cas particulier).
module Slack
  class EventsController < Slack::BaseController
    def create
      if params[:type] == "url_verification"
        # Handshake de configuration : on renvoie le challenge en texte brut.
        render plain: params[:challenge]
      else
        # v1 : aucun event écouté → simple accusé de réception.
        head :ok
      end
    end
  end
end
