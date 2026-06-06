# Controller admin pour la gestion des utilisateurs.
# Permet de rechercher un compte, confirmer manuellement un email
# et renvoyer l'email de confirmation Devise.
module Admin
  class UsersController < BaseController
    # Avant chaque action sur un user spécifique, on charge le user
    before_action :set_user, only: [:confirm, :resend_confirmation]

    # GET /admin/users?q=dorothee
    # Recherche un utilisateur par email ou nom
    def index
      @query = params[:q].to_s.strip

      if @query.present?
        # Recherche dans les emails ET dans les profils (prénom/nom)
        @users = User.joins(:profil)
                     .where(
                       "users.email ILIKE :q OR profils.first_name ILIKE :q OR profils.last_name ILIKE :q",
                       q: "%#{@query}%"
                     )
                     .order(created_at: :desc)
                     .limit(30)
      else
        # Sans recherche : affiche les 20 comptes non confirmés en attente
        @users = User.where(confirmed_at: nil)
                     .order(created_at: :desc)
                     .limit(20)
      end
    end

    # PATCH /admin/users/:id/confirm
    # Confirme manuellement le compte sans envoyer d'email
    def confirm
      if @user.confirmed?
        redirect_to admin_users_path(q: params[:q]),
                    alert: "#{@user.email} est déjà confirmé."
      else
        @user.update!(confirmed_at: Time.current)
        redirect_to admin_users_path(q: params[:q]),
                    notice: "✅ Compte #{@user.email} confirmé manuellement."
      end
    end

    # POST /admin/users/:id/resend_confirmation
    # Renvoie l'email de confirmation Devise
    def resend_confirmation
      if @user.confirmed?
        redirect_to admin_users_path(q: params[:q]),
                    alert: "#{@user.email} est déjà confirmé — pas besoin de renvoyer."
      else
        @user.resend_confirmation_instructions
        redirect_to admin_users_path(q: params[:q]),
                    notice: "📧 Email de confirmation renvoyé à #{@user.email}."
      end
    end

    private

    # Charge le user ciblé par l'action — lève une 404 si introuvable
    def set_user
      @user = User.find(params[:id])
    end
  end
end
