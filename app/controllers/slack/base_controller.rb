# Contrôleur de base pour les endpoints ENTRANTS de Slack (interactivity, commands,
# events). Volontairement PAS un ApplicationController :
#   - pas de Devise (Slack n'a pas de session Teams-up ; l'identité est résolue via
#     SlackIdentity à partir du team_id/user_id signés) ;
#   - pas de Pundit (le `after_action :verify_authorized` d'ApplicationController
#     lèverait sur ces endpoints sans `authorize`) ;
#   - pas de protection CSRF par token (Slack ne peut pas en fournir) → on la
#     désactive et on la remplace par la vérification de signature HMAC.
module Slack
  class BaseController < ActionController::Base
    # Slack poste sans token CSRF → on désactive la protection par formulaire…
    skip_forgery_protection
    # …et on la remplace par la vérification de la signature Slack sur chaque requête.
    include SlackRequestVerification

    before_action :verify_slack_signature!
  end
end
