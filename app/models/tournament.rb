# ── Modèle Tournament ─────────────────────────────────────────────────────────
# Un tournoi regroupe plusieurs joueurs autour d'un sport et d'un format
# (ronde suisse, poules, championnat…). Calqué sur le modèle Match, en plus léger :
# ce Lot 1 couvre la page liste + l'inscription. La mécanique de chaque format
# (tirages, tableaux, scores) arrivera dans les lots suivants.
class Tournament < ApplicationRecord
  # URL propre basée sur le nom (ex: /tournois/open-riviera-winter-a1b2c3).
  include Sluggable
  # Recherche full-text pour la barre de recherche de la page liste.
  include PgSearch::Model

  # ── Associations ────────────────────────────────────────────────────────────
  belongs_to :sport, optional: true
  belongs_to :venue, optional: true
  belongs_to :user,  optional: true # créateur / admin du tournoi

  has_many :tournament_users, dependent: :destroy
  has_many :users, through: :tournament_users

  # Rondes & matchs (Lot 3 — Ronde Suisse + tableau final).
  has_many :tournament_rounds, dependent: :destroy
  has_many :tournament_matches, through: :tournament_rounds

  # Rencontres standard rattachées à ce tournoi (Lot 4) — nullify pour préserver
  # les rencontres (et leur chat) si le tournoi est supprimé.
  has_many :matches, dependent: :nullify

  # ── Constantes métier ────────────────────────────────────────────────────────
  # État du tournoi (voir la catégorisation de la page liste dans le controller).
  STATUSES = %w[open in_progress completed].freeze
  # Formats disponibles. La ronde suisse est le format prioritaire (cf. docs/TOURNOI.md).
  FORMATS  = %w[ronde_suisse poules championnat].freeze

  # Libellés lisibles des formats — source unique de vérité (évite la duplication
  # du dictionnaire dans les vues carte/show).
  FORMAT_LABELS = {
    "ronde_suisse" => "Ronde Suisse",
    "poules" => "Poules",
    "championnat" => "Championnat"
  }.freeze

  # Presets rapides du nombre de joueurs proposés dans le formulaire de création.
  # Ce n'est PAS une contrainte : le mode "Libre" autorise n'importe quel entier.
  PLAYER_COUNTS = [8, 16, 32].freeze

  # Structures figées, dérivées de (format + nombre de joueurs) — rien n'est stocké
  # en base, c'est un simple aperçu en lecture seule affiché à la création.
  # Ronde suisse (Lot 3) : le nombre de rondes est dynamique (3 V pour se qualifier /
  # 3 D pour être éliminé), la seule constante est la taille du tableau final :
  # Final 4 jusqu'à 8 joueurs, Final 8 au-delà (cf. Tournament#final_size).
  # Poules / championnat restent provisoires (formats des lots ultérieurs).
  STRUCTURE_PRESETS = {
    "ronde_suisse" => { 8 => "Ronde suisse (3 V) + Final 4", 16 => "Ronde suisse (3 V) + Final 8", 32 => "Ronde suisse (3 V) + Final 8" },
    "poules" => { 8 => "2 poules de 4 + demi-finales", 16 => "4 poules de 4 + quarts", 32 => "8 poules de 4 + huitièmes" },
    "championnat" => { 8 => "8 joueurs, 7 journées, top 4 en playoffs", 16 => "16 joueurs, top 8 en playoffs",
                       32 => "32 joueurs, top 8 en playoffs" }
  }.freeze

  # ── Recherche full-text (pg_search) ──────────────────────────────────────────
  pg_search_scope :search_by_name,
                  against: %i[name place description],
                  using: { tsearch: { prefix: true } }

  # ── Validations ───────────────────────────────────────────────────────────────
  # Champs marqués d'une étoile dans le formulaire de création : ils doivent être
  # réellement obligatoires côté serveur, pas seulement visuellement dans la vue.
  validates :name, presence: true
  validates :sport, presence: true
  # allow_blank sur inclusion/numericality : évite un 2e message d'erreur
  # redondant (voire une traduction manquante pour "inclusion" en fr.yml)
  # quand le champ est simplement vide — la presence ci-dessus suffit déjà.
  validates :format, presence: true, inclusion: { in: FORMATS, allow_blank: true }
  validates :max_players, presence: true,
                          numericality: { only_integer: true, greater_than: 0, allow_blank: true }
  validates :date, presence: true
  validates :place, presence: true
  validates :status, inclusion: { in: STATUSES }

  # La date/heure d'un tournoi ne peut pas être dans le passé à la création.
  # `on: :create` uniquement : TournamentsController#start et
  # TournamentMatchesController mettent à jour un tournoi (status, scores) alors
  # que sa date est justement arrivée ou dépassée — ne pas casser ces update!.
  validate :date_cannot_be_in_the_past, on: :create

  # ── Scopes ────────────────────────────────────────────────────────────────────
  scope :open_for_registration, -> { where(status: "open") }
  scope :in_progress,           -> { where(status: "in_progress") }
  scope :not_completed,         -> { where.not(status: "completed") }

  # ── Prédicats d'état ────────────────────────────────────────────────────────
  def open?        = status == "open"
  def in_progress? = status == "in_progress"
  def completed?   = status == "completed"

  # Tournoi complet : autant (ou plus) d'inscrits approuvés que de places.
  def full?
    return false if max_players.blank?

    approved_players_count >= max_players
  end

  # Inscriptions réellement ouvertes : statut "open" ET deadline non dépassée.
  # (deadline absente = pas de limite → considérée ouverte.)
  def registration_open?
    open? && (registration_deadline.blank? || registration_deadline.future?)
  end

  # Nombre de joueurs inscrits et approuvés.
  # On ne compte que le rôle "joueur" : l'admin (tournament.user) et le
  # co-organisateur n'occupent pas une place de joueur.
  # (count { } en Ruby → exploite l'association préchargée, pas de requête N+1.)
  def approved_players_count
    tournament_users.count { |tu| tu.status == "approved" && tu.role == "joueur" }
  end

  # Inscriptions « joueur » approuvées, profils préchargés (évite les N+1 sur
  # display_name / avatar dans les onglets Participants et Classement).
  def approved_players
    tournament_users.approved.players.includes(user: :profil)
  end

  # Co-organisateurs approuvés (n'occupent pas de place de joueur).
  def co_organizers
    tournament_users.approved.where(role: "co_organisateur").includes(user: :profil)
  end

  # Classement des joueurs : victoires décroissantes, puis départage set average
  # puis point average (mêmes critères que le seeding — cf. SwissPairing#build_pairs),
  # défaites croissantes en secours, nom en dernier ressort pour un ordre stable.
  def ranked_players
    approved_players.sort_by { |tu| rank_key(tu) }
  end

  # Classement PAR poule (format "poules") : hash ordonné { index_poule => joueurs
  # triés }. Mêmes critères de tri que ranked_players.
  def ranked_pools
    pools.transform_values { |members| members.sort_by { |tu| rank_key(tu) } }
         .sort.to_h
  end

  # Critère de tri du classement (victoires desc, défaites asc, puis set average,
  # point average, nom) — partagé par ranked_players / ranked_pools et le seeding.
  def rank_key(tu)
    [-tu.wins, tu.losses, -tu.set_average, -tu.point_average, tu.display_name]
  end

  # Vrai si `user` organise le tournoi : soit l'admin/créateur, soit un co-organisateur.
  # (Sert aux droits de gestion du tableau à partir du Lot 3.)
  def organizer?(user)
    return false if user.blank?

    user_id == user.id || tournament_users.any? { |tu| tu.user_id == user.id && tu.role == "co_organisateur" }
  end

  # Aperçu de structure figée pour la combinaison (format + nombre de joueurs).
  # nil si la combinaison n'a pas de preset (ex. nombre "Libre" hors 8/16/32).
  def structure_summary
    STRUCTURE_PRESETS.dig(format, max_players)
  end

  # ── Ronde Suisse + tableau final (Lot 3) ─────────────────────────────────────

  # Rondes de la phase suisse, dans l'ordre.
  def swiss_rounds   = tournament_rounds.swiss.ordered
  # Journées de championnat (round-robin intégral), dans l'ordre.
  def league_rounds  = tournament_rounds.league.ordered
  # Journées de poules (round-robin par poule), dans l'ordre.
  def pool_rounds    = tournament_rounds.pool.ordered
  # Tours du tableau final, dans l'ordre.
  def bracket_rounds = tournament_rounds.bracket.ordered
  # Le tableau final a-t-il déjà commencé ?
  def bracket_started? = tournament_rounds.bracket.exists?

  # Ronde en cours : la dernière ronde générée. Le tableau final (bracket) est
  # prioritaire ; sinon la dernière ronde de la phase round-robin du format
  # (un tournoi n'emploie qu'UNE phase round-robin : swiss OU league OU pool).
  def current_round
    bracket_rounds.last ||
      tournament_rounds.where(phase: %w[swiss league pool]).ordered.last
  end

  # Regroupement des joueurs par poule (Lot 5, format "poules").
  # Clé = index de poule (0-based) ; valeur = joueurs de la poule.
  def pools
    approved_players.select { |tu| tu.pool.present? }.group_by(&:pool)
  end

  # Taille du tableau final selon l'effectif inscrit : Final 4 pour un petit
  # tournoi (≤ 8 joueurs), Final 8 au-delà. Aligné sur le seuil du formulaire (< 12 → Final 4
  # côté aperçu, mais on tranche sur l'effectif réel au lancement).
  def final_size
    approved_players_count <= 8 ? 4 : 8
  end

  # Nombre minimal de joueurs pour lancer un tournoi.
  MIN_PLAYERS_TO_START = 2

  # Peut-on lancer le tournoi ? (inscriptions ouvertes + effectif suffisant)
  def startable?
    open? && approved_players_count >= MIN_PLAYERS_TO_START
  end

  # Champ source du slug (utilisé par le concern Sluggable).
  def slug_source = name

  private

  # Rejette une date (et heure si saisie) déjà passée. L'heure reste facultative :
  # sans heure, seule la date est comparée au jour courant.
  def date_cannot_be_in_the_past
    return if date.blank?

    if time.present?
      errors.add(:date, "et l'heure ne peuvent pas être dans le passé") if tournament_datetime < Time.current
    elsif date < Time.zone.today
      errors.add(:date, "ne peut pas être dans le passé")
    end
  end

  def tournament_datetime
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, 0)
  end
end
