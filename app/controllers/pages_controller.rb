class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  # Rails 7.1 vérifie au chargement que les actions dans `only:` existent.
  # PagesController n'a pas d'action `index`, donc on désactive les callbacks Pundit.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def home
    # Récupère les 3 prochains matchs à venir (passés exclus), triés par date puis heure
    @matches = Match
      .where("(date + time) > ?", Time.current)
      .order(date: :asc, time: :asc)
      .limit(3)

    # Match affiché dans la carte hero (droite) :
    # - jamais complet (player_left > 0)
    # - le plus proche dans le temps
    @hero_match = Match
      .where("(date + time) > ?", Time.current)
      .where("player_left > 0")
      .order(date: :asc, time: :asc)
      .first
  end
end
