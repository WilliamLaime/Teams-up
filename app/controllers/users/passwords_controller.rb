# Controller de mot de passe personnalisé.
# Il surcharge Devise::PasswordsController pour :
#   1. Vérifier le captcha hcaptcha avant d'envoyer l'email de reset
#   2. Enregistrer un log de sécurité à chaque demande de reset (légitime ou non)
#
# Tracer les demandes de reset est utile pour détecter une attaque d'énumération
# (un attaquant qui teste des milliers d'emails pour voir lesquels existent).
module Users
  class PasswordsController < Devise::PasswordsController
    # Vérifie le captcha AVANT d'envoyer l'email de reset
    before_action :verify_captcha_on_reset, only: [:create]

    # Surcharge de l'action POST /users/password
    def create
      # Log de sécurité AVANT d'appeler Devise (peu importe si l'email existe ou non)
      email = params.dig(:user, :email).to_s.downcase.strip
      SecurityLog.log("password_reset_request", request, email: email)

      # Appelle la logique Devise standard (envoie l'email si l'utilisateur existe)
      super
    end

    private

    # Vérifie que le widget hcaptcha a bien été complété
    def verify_captcha_on_reset
      return if verify_hcaptcha

      # Recrée un resource vide pour réafficher le formulaire
      self.resource = resource_class.new
      flash.now[:alert] = "Vérification captcha échouée. Veuillez réessayer."
      render :new, status: :unprocessable_entity
    end
  end
end
