# Controller de session personnalisé.
# Il surcharge Devise::SessionsController pour :
#   1. Enregistrer un log de sécurité en cas d'échec de connexion
#   2. Afficher un message flash si la session a expiré (timeout 1h)
#
# Les connexions RÉUSSIES sont loguées dans application_controller.rb
# via la méthode after_sign_in_path_for.
module Users
  class SessionsController < Devise::SessionsController
    # Affiche un message flash si la session a expiré (Devise :timeoutable)
    def new
      # Devise définit flash[:timedout] = true lors du timeout automatique
      # On transforme cela en un message d'alerte lisible
      if flash[:timedout]
        flash[:alert] = I18n.t("devise.failure.timeout")
      end
      super
    end

    # Surcharge de l'action POST /users/sign_in
    def create
      # super appelle la logique Devise normale
      # Le bloc est exécuté APRÈS la tentative d'authentification
      super do |resource|
        # resource.persisted? → true si la connexion a réussi (user trouvé en base)
        # Si false → échec (mauvais mot de passe ou email inexistant)
        unless resource.persisted?
          # Récupère l'email tenté depuis les paramètres du formulaire
          email = params.dig(:user, :email).to_s.downcase.strip
          SecurityLog.log("login_failure", request, email_tente: email)
        end
      end
    end
  end
end
