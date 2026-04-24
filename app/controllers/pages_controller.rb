class PagesController < ApplicationController
  # Ces pages sont publiques (pas besoin d'être connecté)
  skip_before_action :authenticate_user!, only: %i[home about contact partenariat confidentialite conditions offline email_confirmation sitemap]

  # Rails 7.1 vérifie au chargement que les actions dans `only:` existent.
  # PagesController n'a pas d'action `index`, donc on désactive les callbacks Pundit.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def about
    # Pas de données à charger — page statique
    set_meta_tags(
      title:       "Qui sommes-nous ?",
      description: "Découvrez l'histoire de Teams-up, l'application qui connecte les sportifs amateurs pour créer des matchs et former des équipes près de chez eux."
    )
  end

  # Page affichée juste après l'inscription, avant confirmation de l'email.
  # Devise redirige ici via after_inactive_sign_up_path_for (RegistrationsController).
  # L'email est stocké en session pour l'afficher sur la page.
  def email_confirmation
    @confirmation_email = session.delete(:confirmation_pending_email)
  end

  def offline
    # Page affichée par le service worker quand l'utilisateur est hors connexion
    # Le service worker redirige automatiquement ici quand le réseau est coupé
  end

  def contact
    # Initialise un objet vide pour que form_with puisse construire le formulaire
    # Cet objet sera aussi utilisé pour ré-afficher les erreurs si le POST échoue
    @contact_message = ContactMessage.new
    set_meta_tags(
      title:       "Contact",
      description: "Une question, un bug, une suggestion ? Contactez l'équipe Teams-up. Nous répondons sous 48h."
    )
  end

  def partenariat
    # Page statique — présente les opportunités de collaboration professionnelle
    set_meta_tags(
      title:       "Partenariat",
      description: "Devenez partenaire de Teams-up et touchez une communauté de sportifs passionnés. Associations, salles de sport, équipementiers — parlons-en."
    )
  end

  def confidentialite
    # Page Politique de confidentialité — page statique RGPD
    set_meta_tags(
      title:       "Politique de confidentialité",
      # noindex : cette page légale ne doit pas apparaître dans Google
      noindex:     true
    )
  end

  def conditions
    # Page Conditions générales d'utilisation — page statique
    set_meta_tags(
      title:   "Conditions générales d'utilisation",
      # noindex : cette page légale ne doit pas apparaître dans Google
      noindex: true
    )
  end

  def sitemap
    # Page plan du site — liste de tous les liens importants
    # Charge les sports pour la section dédiée
    @sports = Sport.order(:name)
    set_meta_tags(
      title:   "Plan du site",
      noindex: true
    )
  end

  def home
    @available_matches_count = load_available_matches_count
    @matches = load_upcoming_matches
    @hero_match = load_hero_match

    # La page d'accueil a un titre complet sans séparateur — on veut "Teams-up" seul, pas "X | Teams-up"
    set_meta_tags(
      site:        "Teams-up",
      title:       false, # Désactive le titre de page → affiche uniquement le site name
      description: "Crée ou rejoins un match de sport amateur près de chez toi en 30 secondes. Football, basket, tennis et bien plus — #{@available_matches_count} matchs disponibles.",
      og: { title: "Teams-up — Trouve un match de sport amateur" }
    )
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
                   .includes(:sport, :match_users, user: :profil) # évite les N+1 dans _match_card
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
