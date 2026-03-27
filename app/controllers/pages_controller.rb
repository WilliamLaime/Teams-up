class PagesController < ApplicationController
  # Ces pages sont publiques (pas besoin d'être connecté)
  skip_before_action :authenticate_user!, only: %i[home about contact confidentialite conditions]

  # Rails 7.1 vérifie au chargement que les actions dans `only:` existent.
  # PagesController n'a pas d'action `index`, donc on désactive les callbacks Pundit.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def about
    # Pas de données à charger — page statique
  end

  def contact
    # Pas de données à charger — page statique
  end

  def confidentialite
    # Page Politique de confidentialité — page statique RGPD
  end

  def conditions
    # Page Conditions générales d'utilisation — page statique
  end

  def home
    @available_matches_count = load_available_matches_count
    @matches = load_upcoming_matches
    @hero_match = load_hero_match
  end

  private

  # Compte total de tous les matchs disponibles (pas complets, dans le futur, publics)
  # Utilisé pour le badge "X matchs disponibles" dans le hero
  def load_available_matches_count
    Match.upcoming.publicly_visible.where("player_left > 0").count
  end

  # Récupère les 3 prochains matchs à venir publics, filtrés par sport actif si connecté
  def load_upcoming_matches
    matches = Match.upcoming.publicly_visible
                   .visible_for_genre(current_user)  # Cache les matchs "femme uniquement" aux non-femmes
                   .order(date: :asc, time: :asc)
    # Si l'utilisateur est connecté et a un sport actif, on filtre par ce sport
    matches = matches.where(sport_id: current_sport.id) if current_sport.present?
    matches.limit(3)
  end

  # Match affiché dans la carte hero (droite) :
  # - jamais complet (player_left > 0)
  # - le plus proche dans le temps
  # - public uniquement
  # - filtré par sport actif si connecté (cohérent avec la section "Matchs à proximité")
  def load_hero_match
    matches = Match.upcoming.publicly_visible
                   .visible_for_genre(current_user)  # Cache les matchs "femme uniquement" aux non-femmes
                   .where("player_left > 0")
                   .order(date: :asc, time: :asc)
    matches = matches.where(sport_id: current_sport.id) if current_sport.present?
    matches.first
  end
end
