# Controller de session personnalisé.
# Il surcharge Devise::SessionsController pour :
#   1. Vérifier le captcha hcaptcha avant de traiter la connexion
#   2. Enregistrer un log de sécurité en cas d'échec de connexion
#
# Les connexions RÉUSSIES sont loguées dans application_controller.rb
# via la méthode after_sign_in_path_for.
module Users
  class SessionsController < Devise::SessionsController
    # Vérifie le captcha AVANT que Devise ne tente d'authentifier l'utilisateur
    before_action :verify_captcha_before_sign_in, only: [:create]

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

    private

    # Vérifie que le widget hcaptcha a bien été complété par l'utilisateur
    # Si le captcha est invalide → on réaffiche le formulaire avec un message d'erreur
    def verify_captcha_before_sign_in
      return if verify_hcaptcha # verify_hcaptcha retourne true si OK, false sinon

      # Recrée un resource vide pour que la vue puisse réafficher le formulaire
      self.resource = resource_class.new
      flash.now[:alert] = "Vérification captcha échouée. Veuillez réessayer."

      # Réaffiche le formulaire de connexion (status 422 = Unprocessable Entity)
      render :new, status: :unprocessable_entity
    end
  end
end
