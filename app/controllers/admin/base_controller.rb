# Controller de base pour tous les controllers de l'espace admin.
# Tous les controllers admin doivent hériter de celui-ci pour être protégés.
# La sécurité est centralisée ici — si un user n'est pas admin, il est renvoyé à l'accueil.
class Admin::BaseController < ApplicationController
  # Vérifie que l'utilisateur est admin avant chaque action
  before_action :require_admin!

  private

  # Redirige vers l'accueil si l'utilisateur n'est pas admin
  # current_user&.admin? : le & évite une erreur si current_user est nil (user non connecté)
  def require_admin!
    redirect_to root_path, alert: "Accès refusé." unless current_user&.admin?
  end
end
