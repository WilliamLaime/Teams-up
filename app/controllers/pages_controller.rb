class PagesController < ApplicationController
  # about est publique (pas besoin d'être connecté)
  skip_before_action :authenticate_user!, only: [ :home, :about, :about2 ]

  # Rails 7.1 vérifie au chargement que les actions dans `only:` existent.
  # PagesController n'a pas d'action `index`, donc on désactive les callbacks Pundit.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def about
    # Pas de données à charger — page statique
  end

  def about2
    # Version 2 expérimentale — page statique
  end

  def home
    @available_matches_count = load_available_matches_count
    @matches = load_upcoming_matches
    @hero_match = load_hero_match
  end

  private

  # Compte total de tous les matchs disponibles (pas complets, dans le futur)
  # Utilisé pour le badge "X matchs disponibles" dans le hero
  def load_available_matches_count
    Match.upcoming.where("player_left > 0").count
  end

  # Récupère les 3 prochains matchs à venir, triés par date puis heure
  def load_upcoming_matches
    Match.upcoming.order(date: :asc, time: :asc).limit(3)
  end

  # Match affiché dans la carte hero (droite) :
  # - jamais complet (player_left > 0)
  # - le plus proche dans le temps
  def load_hero_match
    Match.upcoming.where("player_left > 0").order(date: :asc, time: :asc).first
  end
end
