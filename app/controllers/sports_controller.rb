# Controller pour la gestion du sport actif de l'utilisateur
class SportsController < ApplicationController
  # Pas besoin de Pundit ici — action simple réservée à l'utilisateur connecté
  # (authenticate_user! est déjà dans ApplicationController)
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # Action switch : change le sport actif de l'utilisateur
  # Appelée via POST /switch_sport/:id depuis le menu navbar
  def switch
    # On cherche le sport demandé parmi TOUS les sports (pas seulement ceux de l'user)
    sport = Sport.find_by(id: params[:id])

    if sport
      # Sauvegarde en session (disponible immédiatement sans recharger l'utilisateur)
      session[:current_sport_id] = sport.id

      # Sauvegarde aussi sur l'utilisateur pour le retrouver en cas de nouvelle session
      current_user.update(current_sport_id: sport.id)

      # Si l'user n'a pas encore ce sport dans ses favoris, on l'ajoute automatiquement
      current_user.sports << sport unless current_user.sports.include?(sport)
    end

    # Retour à la page précédente (ou liste des matchs si pas de "retour")
    redirect_back fallback_location: matches_path
  end

  # Action multisport : passe en mode "tous les sports" (aucun filtre sport)
  def multisport
    # Sentinelle "all" en session → current_sport retournera nil
    session[:current_sport_id] = "all"

    # Efface le sport sauvegardé en base pour la cohérence
    current_user.update(current_sport_id: nil)

    redirect_back fallback_location: matches_path
  end
end
