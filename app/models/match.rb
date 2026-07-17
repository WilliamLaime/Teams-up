class Match < ApplicationRecord
  # URL propre basée sur un slug (ex: /matches/foot-5v5-paris-a1b2c3) — voir Sluggable
  include Sluggable

  # Permet la recherche full-text avec pg_search
  include PgSearch::Model

  # Champ texte servant de base au slug (le titre du match).
  def slug_source
    title
  end

  # Scope de recherche : cherche dans title, place, description du match
  # et dans l'email de l'utilisateur créateur (via la relation belongs_to :user)
  # prefix: true → trouve aussi les mots partiels (ex: "Pari" trouve "Paris")
  pg_search_scope :search_by_title_place_and_creator,
                  against: %i[title place description],
                  associated_against: {
                    profil: %i[first_name last_name] # Cherche aussi par prénom/nom du créateur via user → profil
                  },
                  using: { tsearch: { prefix: true } }

  # Le créateur du match (organisateur)
  belongs_to :user, optional: true

  # Le sport associé à ce match (Football, Tennis, etc.)
  belongs_to :sport, optional: true

  # L'établissement sportif sélectionné via l'autocomplétion (optionnel)
  # nil si l'user a saisi une adresse libre ou un résultat OSM non référencé
  belongs_to :venue, optional: true

  # L'équipe organisatrice de ce match (optionnel — nil pour les matchs publics individuels)
  belongs_to :team, optional: true

  # ── Rattachement à un tournoi (Lot 4) ────────────────────────────────────────
  # tournament       : association lâche (le match "fait partie" du tournoi).
  # tournament_match : lien précis avec une carte du tableau (rencontre planifiée).
  belongs_to :tournament,       optional: true
  belongs_to :tournament_match, optional: true

  has_many :match_users, dependent: :destroy
  has_many :users, through: :match_users

  # Cartes Slack postées pour ce match (suivi du ts pour les MAJ de statut).
  has_many :slack_match_messages, dependent: :destroy

  # Accès direct au profil du créateur (via user) — utilisé par pg_search
  has_one :profil, through: :user
  # Un match a plusieurs messages dans son chat de groupe
  has_many :messages, dependent: :destroy

  # Votes "homme du match" pour ce match
  has_many :match_votes, dependent: :destroy

  # L'élu "homme du match" (calculé automatiquement à partir des votes)
  # nil si aucun vote n'a encore été soumis pour ce match
  belongs_to :homme_du_match, class_name: "User", optional: true

  # ── ActionCable : mises à jour en temps réel ─────────────────────────────
  # Diffuse automatiquement sur le canal "matches" :
  #   - création  → ajoute la carte en bas de la liste (append)
  #   - mise à jour → remplace la carte existante (replace)
  #   - suppression → retire la carte de la page (remove)
  # La vue s'abonne avec <%= turbo_stream_from "matches" %>
  broadcasts_to ->(_match) { "matches" }

  # Avant la suppression, on mémorise la liste des participants (leurs user_id)
  # prepend: true → s'exécute AVANT le dependent: :destroy de match_users
  # sinon match_users est déjà vide au moment du pluck.
  before_destroy :cache_participant_ids, prepend: true

  # Après la suppression du match, retire l'item de chat de la sidebar
  # pour chaque participant connecté, en temps réel via Turbo Stream.
  after_destroy :broadcast_chat_removal

  # Scope public : matchs ouverts à l'inscription (pas encore commencés)
  # Dès l'heure du match → match "verrouillé" : retiré de l'index, on ne peut plus rejoindre
  scope :upcoming, -> { where("(date + time) > ?", Time.current) }

  # Scope visibilité : exclut les matchs privés de l'affichage public
  scope :publicly_visible, -> { where(visibility: "public").or(where(visibility: nil)) }

  # Scope historique : matchs terminés (débutés il y a plus d'1h)
  scope :completed, -> { where("(date + time) < ?", Time.current - 1.hour) }

  # Scope "en cours" pour mes matchs : matchs pas encore terminés
  # (upcoming + verrouillés + en train de se jouer)
  scope :active_for_user, -> { where("(date + time) >= ?", Time.current - 1.hour) }

  # Scope : filtre les matchs selon le genre de l'utilisateur
  # - user nil (visiteur non connecté) → exclut les matchs féminins
  # - user.genre == "femme" → voit tous les matchs (ouverts + féminins)
  # - user.genre == "homme" ou "autre" → ne voit pas les matchs réservés aux femmes
  scope :visible_for_genre, lambda { |user|
    if user.nil? || user.genre != "femme"
      where("genre_restriction = ? OR genre_restriction IS NULL", "tous")
    else
      all
    end
  }

  # ── PRÉ-FILTRES BASÉS SUR LE PROFIL ──────────────────────────────────────────
  # Ces scopes sont utilisés pour pré-filtrer automatiquement les matchs
  # selon les préférences de l'utilisateur (ville, lieux favoris, niveau)

  # Pré-filtre : matchs dans la ville préférée de l'utilisateur
  scope :by_preferred_city, lambda { |city|
    where("place ILIKE ?", "%#{city}%") if city.present?
  }

  # Pré-filtre : matchs dans un des lieux favoris de l'utilisateur
  scope :by_favorite_venues, lambda { |venue_ids|
    where(venue_id: venue_ids) if venue_ids.present? && venue_ids.any?
  }

  # Pré-filtre : matchs au niveau de compétence de l'utilisateur pour un sport
  # Retourne les matchs du même sport avec le même niveau OU "Tout niveau"
  scope :by_user_level_for_sports, lambda { |user_id, sport_id|
    if user_id.present? && sport_id.present?
      # Récupère le niveau de l'user pour ce sport via sa relation sport_profils
      user = User.find_by(id: user_id)
      user_level = user&.profil&.sport_profils&.find_by(sport_id: sport_id)&.level

      # Filter matchs du même sport avec son niveau OU "Tout niveau" (jouable par tous)
      if user_level.present?
        where(sport_id: sport_id)
          .where(level: [user_level, "Tout niveau"])
      end
    else
      all
    end
  }

  # Modes de validation disponibles pour l'organisateur
  VALIDATION_MODES = ["automatic", "manual"].freeze

  # ── Visibilité ───────────────────────────────────────────────────────────────
  # "public"  → visible sur l'index, inscriptions ouvertes à tous
  # "private" → accessible uniquement via le lien avec token
  VISIBILITY_OPTIONS = ["public", "private"].freeze

  # Restrictions de genre disponibles pour un match
  # "tous"    → tout le monde peut rejoindre
  # "feminin" → réservé aux joueuses (genre "femme")
  GENRE_RESTRICTIONS = %w[tous feminin].freeze

  # Génère le token avant la création si le match est privé
  before_create :generate_private_token, if: :private?

  # Retourne vrai si le match est privé
  def private?
    visibility == "private"
  end

  # Retourne vrai si le match est public
  def public?
    visibility == "public" || visibility.blank?
  end

  # Validation : le niveau est obligatoire et doit appartenir à la grille du sport
  validates :level, presence: true
  validate :level_valid_for_sport

  # Validation : capacité cible (joueurs recherchés via l'app) obligatoire, entier, minimum 1.
  # `player_left` (places restantes) n'est plus saisi : il est DÉRIVÉ de players_needed
  # moins les joueurs confirmés (voir recompute_player_left!).
  validates :players_needed,
            presence: true,
            numericality: { only_integer: true, greater_than: 0, message: "doit être au moins 1" }

  # Recalcule les places restantes dès que la capacité cible change
  # (création via new/create, ou édition par l'organisateur).
  # update_column ne redéclenche pas les callbacks → aucune récursion.
  after_save :recompute_player_left!, if: :saved_change_to_players_needed?

  # Rafraîchit le bloc "places" en temps réel quand l'organisateur modifie la
  # capacité, le format ou le nombre de présents (Libre) → le total du ratio change.
  after_update_commit :broadcast_spots,
                      if: -> { saved_change_to_players_needed? || saved_change_to_format? || saved_change_to_players_present? }

  # Si l'organisateur change la date ou les horaires APRÈS avoir partagé le match
  # sur Slack, on resynchronise les cartes postées : rafraîchissement immédiat
  # (le "Quand" affiché change) + reprogrammation des bascules de statut aux
  # nouveaux horaires. Sans ça, les cartes garderaient l'ancienne heure.
  after_update_commit :resync_slack_messages,
                      if: -> { saved_change_to_date? || saved_change_to_time? || saved_change_to_end_time? }

  # Validation : joueurs présents obligatoire uniquement pour le format Libre
  validates :players_present,
            numericality: { only_integer: true, greater_than: 0, message: "doit être au moins 1" },
            if: -> { libre? }

  # Validation : le match doit être prévu au minimum 30 minutes à l'avance
  validate :match_must_be_at_least_30min_in_future, on: %i[create update]

  # Validation : l'heure de fin ne peut pas être identique à l'heure de début
  validate :end_time_differs_from_start, on: %i[create update]

  # Validation : le lien de réservation doit être une URL valide si renseigné
  validates :booking_link, format: {
    with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
    message: "doit être une URL valide (commençant par http:// ou https://)"
  }, allow_blank: true

  # Vérifie que le niveau choisi appartient à la grille du sport sélectionné.
  # Tolère les niveaux hérités ("Tout niveau", "Avancé", etc.) sur les anciens matchs.
  def level_valid_for_sport
    return if level.blank?
    # Backward compat : anciens matchs créés avec "Tout niveau" restent valides
    return if level == "Tout niveau"

    return unless sport.present?

    valid_labels = sport.available_levels.map { |l| l[:label] }
    return if valid_labels.include?(level)

    errors.add(:level, "n'est pas valide pour ce sport (valeurs acceptées : #{valid_labels.join(', ')})")

    # Si pas de sport sélectionné, la validation presence: true sur sport s'en charge
  end

  # Retourne vrai si le format du match est "Libre" (taille d'équipe définie librement)
  def libre?
    format == "Libre"
  end

  # Retourne vrai si le match est en mode validation manuelle
  def manual_validation?
    validation_mode == "manual"
  end

  # Retourne l'inscription de l'organisateur du match
  def organizer_match_user
    match_users.find_by(role: "organisateur")
  end

  # Nombre de joueurs CONFIRMÉS occupant une place (approved, hors organisateur).
  # Les demandes "pending" (validation manuelle) et "waiting" (file d'attente)
  # ne comptent pas tant qu'elles ne sont pas approuvées.
  def confirmed_players_count
    match_users.where(status: "approved").where.not(role: "organisateur").count
  end

  # Recalcule et persiste `player_left` (places restantes) à partir de la source de vérité :
  # capacité cible immuable − joueurs confirmés, borné à 0.
  # Appelé par les callbacks de MatchUser (join/quit/approve/reject/confirm/promotion)
  # et à l'édition de la cible → compteur self-healing, insensible aux dérives.
  # update_column : écriture atomique sans valider ni relancer les callbacks.
  def recompute_player_left!
    update_column(:player_left, [players_needed.to_i - confirmed_players_count, 0].max)
  end

  # Retourne vrai si le match est complet (plus de places disponibles)
  def full?
    player_left.to_i <= 0
  end

  # ── Ratio de places affiché "inscrits / total" ─────────────────────────────
  # Source de vérité partagée par la vue initiale ET le partial diffusé en
  # temps réel (matches/_spots). Le numérateur (secured_players_count) GRANDIT
  # à chaque joueur accepté ; player_left (places libres) diminue d'autant.
  # Ex (18 joueurs) : 1/18 (17 libres) → 2/18 (16 libres) → …

  # Total de joueurs visé par un format chiffré (ex "6v6" → 12), sinon nil.
  def format_total
    return nil unless format.present? && format.match?(/\d+v\d+/i)

    format.scan(/\d+/).map(&:to_i).sum
  end

  # Joueurs occupant une place dans le grid : approuvés + organisateur.
  # `where` interroge toujours la base → valeur fraîche même en broadcast.
  def approved_including_organizer_count
    match_users.where("status = ? OR role = ?", "approved", "organisateur").count
  end

  # Joueurs "sur place" (sans compte app), déduits du total d'un format chiffré.
  def irl_players_count
    total = format_total
    return 0 unless total

    [total - approved_including_organizer_count - player_left.to_i, 0].max
  end

  # Numérateur du ratio = inscrits app (organisateur inclus) + joueurs sur place.
  def secured_players_count
    approved_including_organizer_count + irl_players_count
  end

  # Diffuse le bloc "places" à jour à tous les visiteurs abonnés (turbo_stream_from
  # @match). Appelé après chaque variation du nombre de joueurs (cf callbacks
  # MatchUser) et après édition de la capacité/format par l'organisateur.
  def broadcast_spots
    broadcast_replace_to(
      self,
      target: "match_spots_#{id}",
      partial: "matches/spots",
      locals: { match: self }
    )
  end

  # Retourne vrai si le match a lieu dans moins de 2 heures (et n'est pas encore passé)
  def urgent?
    return false unless date.present? && time.present?

    dt = build_datetime
    dt > Time.current && dt <= Time.current + 2.hours
  end

  # Retourne vrai si le match est déjà passé (date+heure dépassées)
  def past?
    return false unless date.present? && time.present?

    build_datetime < Time.current
  end

  # Retourne vrai si le match est verrouillé (a commencé mais pas encore terminé)
  # = même logique que in_progress? : plus d'inscription possible, match en cours
  def locked?
    in_progress?
  end

  # Retourne vrai si le match est en cours (débuté mais pas encore terminé = < 1h)
  def in_progress?
    return false unless date.present? && time.present?

    dt = build_datetime
    dt <= Time.current && dt > Time.current - 1.hour
  end

  # Retourne vrai si le match est terminé (débuté il y a plus d'1h)
  def completed?
    return false unless date.present? && time.present?

    build_datetime < Time.current - 1.hour
  end

  # Construit un DateTime combinant les champs date et time du match.
  # Public car utilisé par le controller (rappel 24h) et les méthodes internes.
  def build_datetime
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, 0)
  end

  # Heure de fin effective du match.
  # Renvoie l'heure de fin saisie par l'organisateur si elle existe, sinon
  # retombe sur « début + 1h » (matchs créés avant l'ajout du champ end_time).
  # Renvoie nil si l'heure de début n'est pas définie.
  def effective_end_time
    return end_time if end_time.present?
    return unless time.present?

    time + 1.hour
  end

  # Construit le DateTime de fin (date du match + heure de fin effective).
  # Gère le passage après minuit : si l'heure de fin est ≤ l'heure de début
  # (ex. match 23h → 00h30), la fin est reportée au lendemain.
  # Renvoie nil si date ou heure de début manquent.
  def end_datetime
    return unless date.present? && time.present?

    et = effective_end_time
    dt = Time.zone.local(date.year, date.month, date.day, et.hour, et.min, 0)
    dt <= build_datetime ? dt + 1.day : dt
  end

  private

  # Resynchronise les cartes Slack après un changement d'horaire (cf callback).
  # No-op si le match n'a jamais été partagé (aucune carte suivie) → on évite
  # d'enfiler des jobs inutiles. Sinon : MAJ immédiate + reprogrammation.
  def resync_slack_messages
    return unless slack_match_messages.exists?

    SlackMatchStatusJob.perform_later(id)     # rafraîchit le "Quand" affiché maintenant
    SlackMatchStatusJob.schedule_transitions(self) # rebranche les bascules En cours/Terminé

    # Nouvel horaire → on autorise un nouveau rappel "préparez-vous" et on le
    # replanifie (le flag évite les doublons si un ancien job traîne encore).
    update_column(:slack_prep_sent_at, nil) if slack_prep_sent_at.present?
    SlackMatchPrepJob.schedule(self)
  end

  def cache_participant_ids
    # Inclut les joueurs (match_users) + le créateur du match (user_id)
    # car le créateur est stocké sur la colonne user_id du match et peut
    # ne pas avoir de match_users record dans certains cas.
    ids = match_users.pluck(:user_id)
    ids << user_id if user_id.present?
    @participant_ids_before_destroy = ids.uniq
  end

  def broadcast_chat_removal
    @participant_ids_before_destroy.to_a.each do |user_id|
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_conversations_#{user_id}",
        target: "sticky-convo-#{id}"
      )
    end
  end

  # Génère un token URL-safe unique (ex: "aB3xZ9qR")
  # Boucle jusqu'à trouver un token qui n'existe pas encore en base
  def generate_private_token
    loop do
      token = SecureRandom.urlsafe_base64(8)
      unless Match.exists?(private_token: token)
        self.private_token = token
        break
      end
    end
  end

  # Vérifie que le match est prévu au moins 30 min dans le futur
  def match_must_be_at_least_30min_in_future
    return unless date.present? && time.present?

    return unless build_datetime < Time.current + 30.minutes

    errors.add(:base, "Le match doit être prévu au moins 30 minutes à l'avance.")
  end

  # Vérifie que l'heure de fin n'est pas identique à l'heure de début.
  # On autorise une fin « avant » le début (interprétée comme le lendemain,
  # cf. end_datetime), on refuse seulement une durée nulle.
  def end_time_differs_from_start
    return unless time.present? && end_time.present?
    return unless end_time.strftime("%H:%M") == time.strftime("%H:%M")

    errors.add(:end_time, "doit être différente de l'heure de début")
  end
end
