# Chargement DIFFÉRÉ du champ « Partager sur Slack » (turbo-frame).
#
# Pourquoi une requête à part : lister les destinations Slack (channels + membres)
# passe par l'API Slack, donc par le réseau. Rendu dans le cycle de la page, ce coût
# retardait l'affichage COMPLET du formulaire de création de match / tournoi (cf.
# Slack::ChannelLister, dont le résultat est désormais aussi mis en cache 5 min).
# Ici la page part immédiatement et le champ se remplit ensuite, dans son frame.
#
# Ressource strictement personnelle (les destinations de l'utilisateur courant) :
# rien à autoriser via Pundit → skip_authorization, comme Slack::FavoritesController.
module Slack
  class ShareFieldsController < ApplicationController
    # GET /slack/share_field(?standalone=1)
    def show
      skip_authorization

      @standalone = params[:standalone] == "1"
      @slack_destinations = slack_destinations_for(current_user)
    end
  end
end
