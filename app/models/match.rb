class Match < ApplicationRecord
  # Permet la recherche full-text avec pg_search
  include PgSearch::Model

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
  has_many :match_users, dependent: :destroy
  has_many :users, through: :match_users

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
  scope :by_preferred_city, ->(city) {
    where("place ILIKE ?", "%#{city}%") if city.present?
  }

  # Pré-filtre : matchs dans un des lieux favoris de l'utilisateur
  scope :by_favorite_venues, ->(venue_ids) {
    where(venue_id: venue_ids) if venue_ids.present? && venue_ids.any?
  }

  # Pré-filtre : matchs au niveau de compétence de l'utilisateur pour un sport
  # Retourne les matchs du même sport avec le même niveau OU "Tout niveau"
  scope :by_user_level_for_sports, ->(user_id, sport_id) {
    if user_id.present? && sport_id.present?
      # Récupère le niveau de l'user pour ce sport via sa relation sport_profils
      user = User.find_by(id: user_id)
      user_level = user&.profil&.sport_profils&.find_by(sport_id: sport_id)&.level

      # Filter matchs du même sport avec son niveau OU "Tout niveau" (jouable par tous)
      where(sport_id: sport_id)
        .where(level: [user_level, "Tout niveau"]) if user_level.present?
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

  # Validation : nombre de joueurs manquants obligatoire, entier, minimum 1
  validates :player_left,
            presence: true,
            numericality: { only_integer: true, greater_than: 0, message: "doit être au moins 1" }

  # Validation : joueurs présents obligatoire uniquement pour le format Libre
  validates :players_present,
            numericality: { only_integer: true, greater_than: 0, message: "doit être au moins 1" },
            if: -> { libre? }

  # Validation : le match doit être prévu au minimum 30 minutes à l'avance
  validate :match_must_be_at_least_30min_in_future, on: %i[create update]

  # Vérifie que le niveau choisi appartient à la grille du sport sélectionné.
  # Tolère les niveaux hérités ("Tout niveau", "Avancé", etc.) sur les anciens matchs.
  def level_valid_for_sport
    return if level.blank?
    # Backward compat : anciens matchs créés avec "Tout niveau" restent valides
    return if level == "Tout niveau"

    if sport.present?
      valid_labels = sport.available_levels.map { |l| l[:label] }
      unless valid_labels.include?(level)
        errors.add(:level, "n'est pas valide pour ce sport (valeurs acceptées : #{valid_labels.join(', ')})")
      end
    end
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

  # Retourne vrai si le match est complet (plus de places disponibles)
  def full?
    player_left.to_i <= 0
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

  private

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

  # Construit un DateTime combinant les champs date et time du match
  def build_datetime
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, 0)
  end

  # Vérifie que le match est prévu au moins 30 min dans le futur
  def match_must_be_at_least_30min_in_future
    return unless date.present? && time.present?

    return unless build_datetime < Time.current + 30.minutes

    errors.add(:base, "Le match doit être prévu au moins 30 minutes à l'avance.")
  end
end
