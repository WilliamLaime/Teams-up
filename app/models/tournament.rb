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
  # "closed" = inscriptions fermées (complet ou clôture manuelle) mais pas encore lancé.
  STATUSES = %w[open closed in_progress completed].freeze
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
  scope :completed,             -> { where(status: "completed") }

  # Contrepartie SQL de #full?, pour la page "à rejoindre" (paginée : on ne peut
  # pas charger tous les enregistrements en Ruby avant de filtrer). Même seuil
  # que #full? : max_players absent = jamais complet.
  scope :not_full, lambda {
    where(
      "tournaments.max_players IS NULL OR tournaments.max_players > (" \
      "SELECT COUNT(*) FROM tournament_users tu " \
      "WHERE tu.tournament_id = tournaments.id " \
      "AND tu.status = 'approved' AND tu.role = 'joueur')"
    )
  }

  # ── Prédicats d'état ────────────────────────────────────────────────────────
  def open?        = status == "open"
  def closed?      = status == "closed"
  def in_progress? = status == "in_progress"
  def completed?   = status == "completed"

  # Tournoi complet : autant (ou plus) d'inscrits approuvés que de places.
  # (Contrepartie SQL pour les requêtes paginées : scope #not_full.)
  #
  # Requête SQL fraîche (`.count` SANS bloc), plutôt que #approved_players_count (qui
  # compte en Ruby sur l'association potentiellement déjà chargée/mise en cache) :
  # #full? sert de garde-fou juste après une inscription (contrôleur + callback de
  # clôture auto), et une instance de Tournament qui a déjà accédé à
  # `tournament_users` plus tôt dans la même requête renverrait un compte périmé
  # (le joueur qui vient de s'inscrire n'y figurerait pas encore) — un tournoi
  # complet resterait alors « pas plein » à ses propres yeux.
  def full?
    return false if max_players.blank?

    tournament_users.approved.players.count >= max_players
  end

  # Clôture réactive : appelée après chaque inscription (cf. TournamentUser#after_save).
  # Ne fait rien si déjà clôturé/lancé/terminé, ou si le tournoi n'est pas plein.
  def close_registrations_if_full!
    update!(status: "closed") if open? && full?
  end

  # Nombre de joueurs issu d'un preset (8/16/32) plutôt que d'une saisie en mode
  # Libre — sert uniquement à l'affichage ("joueurs" vs "participants attendus").
  def preset_capacity?
    PLAYER_COUNTS.include?(max_players)
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
  # défaites croissantes en secours, draw_order en dernier ressort pour un ordre stable.
  def ranked_players
    approved_players.sort_by { |tu| rank_key(tu) }
  end

  # Classement PAR poule (format "poules") : hash ordonné { index_poule => joueurs
  # triés }. Mêmes critères de tri que ranked_players.
  def ranked_pools
    pools.transform_values { |members| members.sort_by { |tu| rank_key(tu) } }
         .sort.to_h
  end

  # Critère de tri du classement (Lot 6 : points de classement décroissants — barème
  # V/N/D du sport, ou 1 pt/victoire en ronde suisse — puis différentiels de points et
  # de sets décroissants, défaites croissantes, draw_order en dernier ressort — le
  # tirage au sort figé au lancement, pas le nom : évite qu'un tournoi qui saute
  # directement au tableau final sans aucun match joué ne seed toujours les mêmes
  # joueurs en tête par ordre alphabétique) — partagé par ranked_players /
  # ranked_pools et le seeding (BracketBuilder, PoolBuilder).
  def rank_key(tu)
    [-tu.ranking_points, -tu.point_average, -tu.set_average, tu.losses, tu.draw_order]
  end

  # Vrai si `user` organise le tournoi : soit l'admin/créateur, soit un co-organisateur.
  # (Sert aux droits de gestion du tableau à partir du Lot 3.)
  def organizer?(user)
    return false if user.blank?

    user_id == user.id || tournament_users.any? { |tu| tu.user_id == user.id && tu.role == "co_organisateur" }
  end

  # Aperçu de structure figée pour la combinaison (format + nombre de joueurs).
  # nil si la combinaison n'a pas de preset (ex. nombre "Libre" hors 8/16/32).
  # Championnat SANS playoffs (Lot 6) : on réécrit la fin du texte plutôt que de
  # dupliquer STRUCTURE_PRESETS pour une simple variante d'affichage.
  def structure_summary
    preset = STRUCTURE_PRESETS.dig(format, max_players)
    return preset if preset.nil? || format != "championnat" || playoffs?

    preset.sub(/,\s*top \d+ en playoffs/, ", vainqueur = 1er du classement")
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

  # Ce tournoi aura-t-il un tableau final (à un moment ou un autre) ? Ronde
  # suisse et poules en ont TOUJOURS un (cf. SwissPairing/PoolBuilder, aucun
  # test sur `playoffs`) ; seul le championnat peut s'en passer (Lot 6, réglage
  # `playoffs`, cf. LeagueBuilder#next_round! qui ne bascule sur le tableau
  # final QUE si `playoffs?`). Attention : la colonne `playoffs` existe pour
  # TOUS les tournois (valeur par défaut true en base) mais n'a de sens que
  # pour le championnat — un tournoi poules/suisse peut très bien porter
  # `playoffs: false` en base (jamais lu par son moteur) sans que ça change
  # quoi que ce soit : ne JAMAIS tester `playoffs?` seul hors championnat
  # (cf. _board.html.erb / _phase_nav.html.erb, qui utilisent ce prédicat).
  def bracket_expected?
    format != "championnat" || playoffs?
  end

  # Bilan V/D de chaque joueur EN ENTRANT dans chaque ronde suisse (avant que
  # cette ronde soit jouée) — sert à regrouper visuellement les matchs d'un
  # tour par « bracket de score » (2V-0D / 1V-1D / 0V-2D…, cf. onglet Matchs).
  # Différent de TournamentUser#wins/#losses (bilan cumulé ACTUEL) qui inclut
  # aussi les rondes postérieures une fois qu'elles ont été jouées — on ne peut
  # donc pas s'en servir tel quel pour étiqueter un tour déjà terminé depuis.
  # Renvoie { numéro_de_ronde => { tournament_user_id => [victoires, défaites] } }.
  def swiss_entering_records
    tally = Hash.new { |h, k| h[k] = [0, 0] }
    records = {}

    swiss_rounds.each do |round|
      records[round.number] = tally.dup

      round.tournament_matches.reject(&:is_bye).select(&:decided?).each do |match|
        loser_id = match.winner_id == match.player_a_id ? match.player_b_id : match.player_a_id
        tally[match.winner_id] = [tally[match.winner_id][0] + 1, tally[match.winner_id][1]]
        tally[loser_id]        = [tally[loser_id][0], tally[loser_id][1] + 1]
      end
    end

    records
  end

  # Vainqueur du tournoi (Lot 6) — source unique pour l'onglet Vue d'ensemble ET
  # l'onglet Classement. Tableau final joué (ronde suisse / poules / championnat AVEC
  # playoffs) → vainqueur du dernier match du bracket. Championnat SANS playoffs →
  # le 1er du classement final, puisqu'il n'y a pas de tableau à l'issue de la saison.
  def champion
    return nil unless completed?
    return bracket_rounds.last&.tournament_matches&.first&.winner if bracket_started?

    ranked_players.first if format == "championnat"
  end

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

  # Nombre de poules (~4 joueurs par poule, cf. STRUCTURE_PRESETS "poules") — seule
  # source de vérité, réutilisée par PoolBuilder pour la répartition ET ici pour
  # dimensionner le tableau final (2 qualifiés par poule, cf. #final_size).
  def pool_count
    [(approved_players_count / 4.0).ceil, 1].max
  end

  # Taille du tableau final selon le format :
  #   - poules : le double du nombre de poules — les 2 premiers de chaque poule
  #     (règle classique, ex. Coupe du monde) — reproduit exactement
  #     STRUCTURE_PRESETS["poules"] : 2 poules de 4 → demi-finales (4), 4 poules →
  #     quarts (8), 8 poules → huitièmes (16).
  #   - ronde suisse / championnat : Final 4 pour un petit tournoi (≤ 8 joueurs),
  #     Final 8 au-delà (aligné sur le seuil du formulaire, plafond volontaire —
  #     contrairement aux poules, ne grandit pas avec l'effectif au-delà de 8).
  def final_size
    return pool_count * 2 if format == "poules"

    approved_players_count <= 8 ? 4 : 8
  end

  # Nombre de tours qu'aura le tableau final une fois complet (ex. final_size 16
  # → 4 tours : 8es, quarts, demies, finale) — sert à afficher la structure
  # complète du tableau dès son lancement, avec des cases "À déterminer" pour les
  # tours pas encore joués (cf. _bracket.html.erb).
  def expected_bracket_round_count
    Math.log2(final_size).to_i
  end

  # Nombre minimal de joueurs pour lancer un tournoi.
  MIN_PLAYERS_TO_START = 2

  # Peut-on lancer le tournoi ? (inscriptions ouvertes ou tout juste clôturées,
  # + effectif suffisant)
  def startable?
    (open? || closed?) && approved_players_count >= MIN_PLAYERS_TO_START
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
