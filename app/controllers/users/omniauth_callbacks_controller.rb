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
        # L'utilisateur a bien été trouvé ou créé → on le connecte
        sign_in_and_redirect @user, event: :authentication

        # Afficher un message de bienvenue si ce n'est pas déjà fait
        set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      else
        # Quelque chose s'est mal passé (email déjà pris avec autre méthode, etc.)
        # On stocke temporairement les données OAuth pour les réafficher dans le formulaire
        session["devise.google_data"] = request.env["omniauth.auth"].except(:extra)
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
      end
    end

    # Appelé si l'utilisateur annule la connexion Google
    def failure
      redirect_to root_path, alert: "Connexion annulée."
    end
  end
end
