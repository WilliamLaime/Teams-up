# Ce controller gère les "callbacks" OAuth, c'est-à-dire les redirections
# que Google envoie vers notre application après que l'utilisateur s'est connecté.
module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    # Cette action est appelée automatiquement par Devise quand Google
    # redirige l'utilisateur vers /users/auth/google_oauth2/callback
    def google_oauth2
      # auth contient toutes les infos renvoyées par Google :
      # - auth.info.email    → l'email de l'utilisateur
      # - auth.info.name     → le nom complet
      # - auth.info.image    → l'URL de la photo de profil Google
      # - auth.uid           → identifiant unique Google de cet utilisateur
      # - auth.provider      → "google_oauth2"
      @user = User.from_omniauth(request.env["omniauth.auth"])

      if @user.persisted?
        # Log de sécurité : connexion Google réussie
        SecurityLog.log("google_login", request, user: @user)

        # L'utilisateur a bien été trouvé ou créé → on le connecte
        sign_in_and_redirect @user, event: :authentication

        # Afficher un message de bienvenue si ce n'est pas déjà fait
        set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      else
        # Quelque chose s'est mal passé (validation échouée, email déjà pris, etc.)
        # On stocke temporairement les données OAuth pour les réafficher dans le formulaire
        session["devise.google_data"] = request.env["omniauth.auth"].except(:extra)
        # Message d'erreur lisible ou message générique si pas d'erreur de validation
        error_message = @user.errors.full_messages.presence&.join(", ") ||
                        "Impossible de créer le compte avec Google. Réessaie ou inscris-toi manuellement."
        redirect_to new_user_registration_url, alert: error_message
      end
    rescue StandardError => e
      # Filet de sécurité : si from_omniauth lève une exception inattendue,
      # on redirige proprement au lieu d'afficher une page d'erreur 500.
      Rails.logger.error("[OmniAuth] Erreur Google OAuth : #{e.class} — #{e.message}")
      redirect_to new_user_session_url,
                  alert: "Une erreur est survenue lors de la connexion avec Google. Réessaie dans quelques instants."
    end

    # Appelé si l'utilisateur annule la connexion Google ou si OmniAuth détecte une erreur
    # (ex : state mismatch CSRF, timeout, accès refusé côté Google)
    def failure
      redirect_to new_user_session_url, alert: "Connexion avec Google annulée ou expirée. Réessaie."
    end
  end
end
