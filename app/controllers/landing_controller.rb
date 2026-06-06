# Contrôleur de la landing page "Bientôt disponible".
# Accessible à tous sans authentification — c'est la vitrine publique du site
# avant le lancement officiel.
class LandingController < ApplicationController
  # La landing est publique — on désactive toutes les restrictions héritées
  skip_before_action :authenticate_user!
  skip_after_action  :verify_authorized
  skip_after_action  :verify_policy_scoped

  # Utilise le layout minimal dédié (sans navbar, footer, modales, etc.)
  layout "landing"

  # GET /
  # Redirige les utilisateurs déjà connectés (développeurs) vers les matchs
  # pour qu'ils puissent continuer à utiliser le site normalement.
  def index
    redirect_to matches_path if user_signed_in?
  end

  # POST /inscription
  # Enregistre l'email du visiteur dans la waitlist.
  # Répond par un flash + redirection (pas de Turbo stream pour rester simple).
  def subscribe
    entry = WaitlistEntry.new(email: params[:email])

    if entry.save
      flash[:notice] = "Merci ! Tu seras parmi les premiers à être informé du lancement."
    elsif entry.errors.of_kind?(:email, :taken)
      # Email déjà connu — message rassurant plutôt qu'une erreur brute
      flash[:notice] = "Cette adresse est déjà enregistrée. On te tient au courant !"
    else
      flash[:alert] = "Adresse email invalide. Vérifie et réessaie."
    end

    redirect_to root_path
  end
end
