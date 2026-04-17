class ApplicationController < ActionController::Base
  # ── Redirection 301 : .com → .fr ──────────────────────────────────────────
  # Doit être le PREMIER before_action pour intercepter toutes les requêtes
  # avant toute logique métier (auth, meta tags, etc.).
  # 301 = redirection permanente → Google transfère tout le "link juice" SEO vers le .fr
  before_action :redirect_com_to_fr

  before_action :authenticate_user!
  # Initialise les meta tags SEO par défaut avant chaque action.
  # Chaque controller peut appeler set_meta_tags() pour surcharger ces valeurs.
  before_action :set_default_meta_tags
  include Pundit::Authorization

  # Pundit: allow-list approach
  # On n'utilise pas `only:` ni `except:` pour éviter l'erreur Rails 7.1
  # qui vérifie au chargement si l'action existe dans tous les sous-contrôleurs (Devise, etc.)
  # La condition est gérée dans les méthodes skip_* ci-dessous.
  after_action :verify_authorized, unless: :skip_pundit_verify_authorized?
  after_action :verify_policy_scoped, unless: :skip_pundit_verify_policy_scoped?

  # Si l'utilisateur n'est pas autorisé, on affiche un message et on le redirige
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Rend current_sport et multisport_mode? accessibles dans toutes les vues
  helper_method :current_sport, :multisport_mode?

  # Avant chaque action : charge les données de la modal de review si le flag est présent
  # Le flag est posé par after_sign_in_path_for juste après le login
  before_action :load_review_modal_data

  # Avant chaque action : détermine si la modale ou le banner d'onboarding doit s'afficher
  before_action :set_onboarding_flags

  # Retourne true si l'utilisateur est en mode "Multisport" (tous les sports)
  def multisport_mode?
    user_signed_in? && session[:current_sport_id] == "all"
  end

  # Retourne le sport actuellement actif pour l'utilisateur connecté
  # Priorité : 1) mode multisport → nil  2) session  3) base  4) premier sport
  def current_sport
    return nil unless user_signed_in?
    # Mode multisport explicitement sélectionné → aucun sport actif
    return nil if multisport_mode?

    sport_id = session[:current_sport_id] || current_user.current_sport_id
    Sport.find_by(id: sport_id) || current_user.sports.first
  end

  private

  # ── Redirection permanente tous domaines → www.teams-up-sport.fr ──────────
  #
  # Domaines Heroku détectés (tous redirigent vers le domaine canonique) :
  #   - teams-up-sport.com       (sans www)
  #   - www.teams-up-sport.com
  #   - teams-up-sport.fr        (sans www)
  #   - www.teams-up.fit
  #
  # Le domaine canonique (jamais redirigé) : www.teams-up-sport.fr
  #
  # 301 = redirection permanente → Google transfère tout le "link juice" SEO
  # vers un seul domaine au lieu de le diluer sur 3.
  CANONICAL_HOST = "www.teams-up-sport.fr".freeze

  def redirect_com_to_fr
    # En développement ou test, on ne redirige pas (host = localhost)
    return if Rails.env.local?
    # Si on est déjà sur le bon domaine, rien à faire
    return if request.host == CANONICAL_HOST

    redirect_to "https://#{CANONICAL_HOST}#{request.fullpath}",
                status:           :moved_permanently, # 301 — permanent pour Google
                allow_other_host: true                # Rails 7+ exige ce flag cross-domain
  end

  # ── Meta tags SEO par défaut ───────────────────────────────────────────────
  #
  # Ces valeurs s'appliquent à toutes les pages tant qu'un controller ne les
  # surcharge pas avec set_meta_tags(). Elles garantissent qu'aucune page
  # ne part jamais sans title ni description dans les résultats Google.
  #
  # Structure du title généré : "Page spécifique | Teams-up"
  # Si aucun titre n'est défini : "Teams-up — Sport, matchs et équipes"
  def set_default_meta_tags
    set_meta_tags(
      # Nom du site — apparaît après le séparateur " | " dans le title
      site:        "Teams-up",
      # Title par défaut utilisé si la page ne définit pas le sien
      title:       "Sport, matchs et équipes",
      # Description par défaut — affichée sous le titre dans les résultats Google
      description: "Teams-up — Crée ou rejoins un match de sport amateur près de chez toi. Football, basket, tennis et plus. Inscris-toi gratuitement.",
      # Séparateur entre le titre de la page et le nom du site
      separator:   "|",
      # ── OpenGraph (partage sur réseaux sociaux : Facebook, LinkedIn, WhatsApp) ──
      og: {
        site_name:   "Teams-up",
        type:        "website",
        # :title et :description font référence aux valeurs définies ci-dessus
        title:       :title,
        description: :description,
        url:         -> { request.original_url }
      },
      # ── Twitter Card (partage sur X/Twitter) ──
      twitter: {
        card:        "summary",
        title:       :title,
        description: :description
      },
      # ── Canonical URL ──────────────────────────────────────────────────────
      # Pointe toujours vers l'URL propre sans query string.
      # Exemple : /matches?sport=2&page=3 → canonical = https://www.teams-up.fr/matches
      # Ça évite que Google considère chaque combinaison de filtres comme une page distincte
      # (ce qui diluerait le score SEO de la vraie page /matches).
      canonical: -> { request.base_url + request.path }
    )
  end

  # Redirige l'utilisateur non autorisé avec un message d'alerte
  def user_not_authorized
    flash[:alert] = "Vous n'êtes pas autorisé à effectuer cette action."
    redirect_back(fallback_location: root_path)
  end

  # verify_authorized s'applique à toutes les actions SAUF index
  def skip_pundit_verify_authorized?
    skip_pundit? || action_name == "index"
  end

  # verify_policy_scoped s'applique UNIQUEMENT à l'action index
  def skip_pundit_verify_policy_scoped?
    skip_pundit? || action_name != "index"
  end

  # Ignore Pundit pour Devise et les pages publiques
  def skip_pundit?
    devise_controller? || params[:controller] =~ /(^(rails_)?admin)|(^pages$)/
  end

  # ── Onboarding post-inscription ──────────────────────────────────────────

  # Détecte si l'utilisateur connecté a besoin de voir la modale d'onboarding
  # ou le banner de rappel (7 jours après, profil incomplet).
  #
  # IMPORTANT : on ne marque PAS onboarding_shown_at ici.
  # Le flag est posé uniquement quand l'utilisateur clique l'un des deux boutons
  # de la modale (via ProfilsController#dismiss_onboarding).
  # Cela garantit que la modale est affichée jusqu'à ce que l'user l'ait vraiment vue,
  # même si Devise l'a redirigé à travers plusieurs pages après la confirmation d'email.
  def set_onboarding_flags
    return unless user_signed_in?

    profil = current_user.profil
    return unless profil

    if profil.needs_onboarding_modal?
      @show_onboarding_modal = true
    elsif profil.needs_profile_reminder?
      @show_profile_reminder_banner = true
    end
  end

  # ── Système de modal post-match ───────────────────────────────────────────

  # Hook Devise : appelé automatiquement après chaque connexion réussie
  # On pose un flag en session pour déclencher la modal au prochain chargement de page
  # On enregistre aussi un log de sécurité
  def after_sign_in_path_for(resource)
    SecurityLog.log("login_success", request, user: resource)
    session[:show_review_modal] = true
    super
  end

  # Charge les données de la modal si le flag de session est présent
  # session.delete retire le flag → la modal ne s'affiche qu'une fois par connexion
  def load_review_modal_data
    return unless user_signed_in?

    # Sur la page show d'un match, on ne consomme pas le flag — la page a son propre bouton
    # Le flag sera affiché sur la prochaine page visitée
    return if controller_name == "matches" && action_name == "show"

    return unless session.delete(:show_review_modal)

    # Trouve les matchs terminés récents avec des joueurs non encore notés
    @pending_review_matches = find_pending_reviews_for_modal
  end

  # Retourne un tableau de { match:, users: [...] } pour la modal
  # Chaque élément = 1 match + liste des co-joueurs pas encore notés
  #
  # Optimisation N+1 : toutes les données sont chargées en amont en ~6 requêtes fixes,
  # quelle que soit le nombre de matchs. La boucle each ne fait que des lookups Hash O(1).
  def find_pending_reviews_for_modal
    # Matchs où current_user a été approuvé
    my_match_ids = current_user.match_users.where(status: "approved").pluck(:match_id)
    return [] if my_match_ids.empty?

    # Filtre : terminé (>1h) ET dans les 7 derniers jours
    # .to_a force l'évaluation maintenant pour récupérer les IDs ci-dessous
    recent_completed_matches = Match.where(id: my_match_ids)
                                    .where("(date + time) < ?", Time.current - 1.hour)
                                    .where("(date + time) > ?", Time.current - 7.days - 1.hour)
                                    .to_a
    return [] if recent_completed_matches.empty?

    match_ids = recent_completed_matches.map(&:id)

    # ── 1 seule requête pour tous les co-joueurs approuvés de tous les matchs ──
    # group_by + transform_values produit : { match_id => [user_id, user_id, ...] }
    co_players_by_match = MatchUser.where(match_id: match_ids, status: "approved")
                                   .where.not(user_id: current_user.id)
                                   .pluck(:match_id, :user_id)
                                   .group_by(&:first)
                                   .transform_values { |rows| rows.map(&:last) }

    all_co_player_ids = co_players_by_match.values.flatten.uniq

    # ── 1 seule requête pour les avis déjà donnés — filtrée sur CES matchs uniquement ──
    # (évite de charger l'historique complet de l'utilisateur)
    already_reviewed = Avis.where(reviewer_id: current_user.id, match_id: match_ids)
                           .pluck(:reviewed_user_id, :match_id)
                           .map { |uid, mid| "#{uid}-#{mid}" }

    # ── 1 seule requête pour les votes homme du match — filtrée sur CES matchs ──
    already_voted_match_ids = MatchVote.where(voter_id: current_user.id, match_id: match_ids)
                                       .pluck(:match_id)

    # ── 1 seule requête pour tous les users + profil (LEFT JOIN via eager_load) ──
    # eager_load fait un LEFT OUTER JOIN users/profils en 1 requête (vs 2 avec includes)
    # Ce choix réduit le total à 6 requêtes fixes au lieu de 7.
    users_by_id = User.where(id: all_co_player_ids).eager_load(:profil).index_by(&:id)

    # ── Boucle sans aucune requête SQL — lookups Hash O(1) uniquement ──
    result = []

    recent_completed_matches.each do |match|
      # Co-joueurs de ce match (déjà en mémoire, pas de requête)
      co_player_ids = co_players_by_match[match.id] || []

      # Co-joueurs pas encore notés dans CE match
      pending_ids = co_player_ids.reject { |uid| already_reviewed.include?("#{uid}-#{match.id}") }

      # A-t-on déjà voté pour l'homme du match de ce match ?
      has_voted = already_voted_match_ids.include?(match.id)

      # Le vote homme du match n'a du sens que si des co-joueurs existent
      # (évite d'afficher la section si le créateur est seul ou si co_player_ids est vide)
      can_vote_homme = !has_voted && co_player_ids.any?

      # On inclut le match si des reviews sont pending OU si on peut encore voter homme du match
      next unless pending_ids.any? || can_vote_homme

      pending_users  = users_by_id.values_at(*pending_ids).compact
      all_co_players = users_by_id.values_at(*co_player_ids).compact

      result << {
        match: match,
        users: pending_users,           # joueurs à noter (review)
        all_co_players: all_co_players, # tous les joueurs (vote homme du match)
        has_voted: has_voted,           # true si déjà voté pour ce match
        can_vote_homme: can_vote_homme  # true si la section homme du match doit s'afficher
      }
    end

    result
  end
end
