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

  # Affectation des chapeaux (Lot 7) : le panneau de constitution des poules
  # enregistre les `pot` de tous les inscrits en une seule requête. Le `reject_if`
  # borne le mécanisme à la MISE À JOUR : sans lui, un bloc d'attributs sans `id`
  # tenterait de créer une inscription. Et un `id` étranger au tournoi lève
  # RecordNotFound, l'association servant elle-même de contrôle d'accès.
  accepts_nested_attributes_for :tournament_users, reject_if: ->(attrs) { attrs[:id].blank? }

  # Rondes & matchs (Lot 3 — Ronde Suisse + tableau final).
  has_many :tournament_rounds, dependent: :destroy
  has_many :tournament_matches, through: :tournament_rounds

  # Rencontres standard rattachées à ce tournoi (Lot 4) — nullify pour préserver
  # les rencontres (et leur chat) si le tournoi est supprimé.
  has_many :matches, dependent: :nullify

  # ── Ordre de suppression ────────────────────────────────────────────────────
  # `dependent: :destroy` est implémenté par un before_destroy posé À LA
  # DÉCLARATION de l'association : les inscrits (ligne 17) partaient donc avant les
  # tours (ligne 28). Or tournament_matches porte trois clés étrangères vers
  # tournament_users (player_a_id, player_b_id, winner_id) → PG::ForeignKeyViolation
  # dès qu'un tournoi avait le moindre match.
  #
  # `prepend: true` place ce hook AVANT ceux des has_many, ce qui vide les tours (et
  # leurs matchs) en premier. Un hook explicite plutôt qu'une réorganisation des
  # `has_many` : l'ordre de déclaration comme garantie de fonctionnement est un
  # piège qu'un simple déplacement de ligne rouvrirait sans bruit.
  before_destroy :destroy_rounds_before_players, prepend: true

  # ── Constantes métier ────────────────────────────────────────────────────────
  # État du tournoi (voir la catégorisation de la page liste dans le controller).
  # "closed" = inscriptions fermées (complet ou clôture manuelle) mais pas encore lancé.
  STATUSES = %w[open closed in_progress completed].freeze
  # Formats disponibles. La ronde suisse est le format prioritaire (cf. docs/TOURNOI.md).
  #
  # "criterium_federal" est un format À PART, et non une option de "poules" : les
  # tournois « Poules » existants doivent garder exactement leur comportement, et
  # l'organisateur doit choisir le règlement FFTT en connaissance de cause (matchs
  # de classement, consolante, barème 2/1 — cf. CriteriumStructure).
  FORMATS  = %w[ronde_suisse poules championnat criterium_federal].freeze

  # Libellés lisibles des formats — source unique de vérité (évite la duplication
  # du dictionnaire dans les vues carte/show).
  FORMAT_LABELS = {
    "ronde_suisse" => "Ronde Suisse",
    "poules" => "Poules",
    "championnat" => "Championnat",
    "criterium_federal" => "Critérium Fédéral"
  }.freeze

  # Phases postérieures aux poules du Critérium. Regroupées ici parce que plusieurs
  # décisions en dépendent : les règles de score renforcées (best_of 7, cf.
  # TournamentMatch#final_phase?), la détection « la phase finale a commencé », et
  # l'invalidation de l'aval lors d'une correction de score.
  FINAL_PHASES = %w[barrage bracket consolation classification].freeze

  # Formats qui commencent par une phase de poules et dimensionnent donc leur
  # tableau final sur le NOMBRE DE POULES (2 sortants par poule) et non sur
  # l'effectif — cf. #recommended_final_size / #planned_final_size.
  POOL_BASED_FORMATS = %w[poules criterium_federal].freeze

  # ── Variantes de phase finale du Critérium (Lot 6) ──────────────────────────
  # Le règlement FFTT ne joue pas le même tournoi selon l'effectif :
  #
  #   "standard" — barrages + tableau final + consolante. Le format de référence,
  #                à partir de 17 joueurs (assez de poules pour que les barrages
  #                aient un sens et que la consolante se remplisse).
  #   "integral" — « classement intégral » : un SEUL tableau, tout le monde dedans,
  #                aucun barrage, et aucun ex æquo — chaque place se joue. C'est la
  #                variante des effectifs réduits (8 à 16), où découper en barrages
  #                + consolante produirait des tableaux de 2 ou 4 joueurs.
  #   "none"     — jusqu'à 7 joueurs, une poule unique suffit : le classement final
  #                EST le classement de la poule, il n'y a aucune phase finale.
  #
  # La colonne `final_phase_mode` est une échappatoire (nil = déduit de l'effectif,
  # cf. #criterium_mode) : c'est le seuil d'effectif qui est la règle, pas un choix.
  CRITERIUM_MODES = %w[standard integral none].freeze

  # Seuils d'effectif du règlement, lus par #criterium_mode et #pool_plan.
  #   ≤ 7  → poule unique, pas de phase finale
  #   ≤ 10 → 2 poules   ·  11 → 3 poules (4/4/3)  ·  ≤ 16 → 4 poules
  # au-delà : la règle générique (effectif / taille de poule).
  CRITERIUM_POOLS_ONLY_MAX = 7
  CRITERIUM_INTEGRAL_MAX   = 16

  # ── Constitution des poules (Lot 7) ─────────────────────────────────────────
  #   "random" — tirage au sort intégral : serpentin sur `draw_order` (défaut).
  #   "pots"   — chapeaux : chaque chapeau numéroté fournit un joueur par poule,
  #              le reste (« chapeau général ») complète. C'est l'organisateur qui
  #              affecte les joueurs aux chapeaux, à la main.
  # Cf. PoolSeeding, qui applique l'un ou l'autre.
  POOL_SEEDING_MODES = %w[random pots].freeze
  DEFAULT_POT_COUNT  = 2

  # Presets rapides du nombre de joueurs proposés dans le formulaire de création.
  # Ce n'est PAS une contrainte : le mode "Libre" autorise n'importe quel entier.
  PLAYER_COUNTS = [8, 16, 32].freeze

  # Nom du tour d'entrée d'un tableau final selon sa taille (4 places → on entre en
  # demi-finales). Sert aux résumés de structure ; au-delà de 16, on nomme la taille.
  BRACKET_STAGE_NAMES = { 2 => "finale", 4 => "demi-finales", 8 => "quarts", 16 => "huitièmes" }.freeze

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
  # max_players VIDE = effectif libre : aucun plafond, on verra bien combien de
  # personnes s'inscrivent. Ce n'est pas un oubli de saisie mais un choix, d'où
  # l'absence de `presence` — même convention que les autres réglages de
  # structure (players_per_pool, bracket_size…), où NULL veut dire « pas fixé ».
  # La structure du tournoi n'a de toute façon jamais besoin de ce nombre pour
  # fonctionner : elle se calcule au lancement sur les inscrits réels, et
  # max_players ne sert qu'à plafonner les inscriptions et à annoncer à l'avance
  # ce que ça donnera.
  validates :max_players, numericality: { only_integer: true, greater_than: 0, allow_blank: true }
  validates :date, presence: true
  validates :place, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Réglages de structure (Lot 7) — tous facultatifs : vide = valeur recommandée.
  # Une poule se joue à 2 joueurs minimum ; il faut au moins 1 victoire pour se
  # qualifier et 1 défaite pour être éliminé (sinon la ronde suisse ne finirait jamais).
  validates :players_per_pool, numericality: { only_integer: true, greater_than_or_equal_to: 2 }, allow_nil: true
  validates :swiss_wins_to_qualify, :swiss_losses_to_eliminate,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  # Le tableau final se joue par élimination directe : sa taille doit être une
  # puissance de 2 (4 = demies, 8 = quarts, 16 = huitièmes…), sinon les tours ne
  # s'enchaînent pas (cf. BracketBuilder + #expected_bracket_round_count).
  validates :bracket_size, numericality: { only_integer: true, greater_than_or_equal_to: 2 }, allow_nil: true
  validate  :bracket_size_is_power_of_two
  # Le Critérium Fédéral ne connaît que les poules de 3 ou de 4 : c'est la taille
  # qui détermine les sortants (1er qualifié, 2e et 3e en barrage, 4e directement
  # en consolante). À 5 joueurs par poule, le règlement ne dit plus rien du 5e —
  # et CriteriumStructure ne saurait pas où le faire entrer.
  validate :criterium_pool_size_is_three_or_four
  # Variante de phase finale : vide = déduite de l'effectif (cf. #criterium_mode).
  validates :final_phase_mode, inclusion: { in: CRITERIUM_MODES }, allow_blank: true
  # Constitution des poules : vide = "random". Il faut au moins un chapeau pour
  # que le mode "pots" veuille dire quelque chose.
  validates :pool_seeding_mode, inclusion: { in: POOL_SEEDING_MODES }, allow_blank: true
  validates :seeded_pot_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true

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

  # Effectif libre : aucun plafond annoncé. Le tournoi ne sera jamais « complet »
  # (cf. #full?), n'est jamais clôturé automatiquement, et sa structure ne peut
  # être annoncée qu'au lancement, une fois les inscrits connus.
  def unlimited_capacity?
    max_players.blank?
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

  # Co-organisateurs approuvés : ceux qui portent les DROITS de gestion, lus sur la
  # colonne `co_organizer` et non sur le rôle. Un co-organisateur peut donc être
  # inscrit comme joueur — il figure alors dans `approved_players` ET ici.
  def co_organizers
    tournament_users.approved.co_organizers.includes(user: :profil)
  end

  # Classement des joueurs : victoires décroissantes, puis départage set average
  # puis point average (mêmes critères que le seeding — cf. SwissPairing#build_pairs),
  # défaites croissantes en secours, draw_order en dernier ressort pour un ordre stable.
  def ranked_players
    approved_players.sort_by { |tu| rank_key(tu) }
  end

  # Classement PAR poule (format "poules") : hash ordonné { index_poule => joueurs
  # triés }. Mêmes critères de tri que ranked_players.
  #
  # En Critérium Fédéral, c'est le règlement FFTT qui départage (points-parties 2/1,
  # confrontation directe puis quotients restreints au sous-groupe d'ex-æquo) — une
  # logique que `rank_key`, clé de tri plate, ne peut pas exprimer. D'où la
  # délégation à PoolStandings, qui est aussi ce qui décide des sortants de poule.
  def ranked_pools
    return pool_standings.transform_values(&:ordered) if criterium?

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
  #
  # `draw_order.to_i` et non `draw_order` : la colonne est nullable (aucun backfill
  # sur les tournois lancés avant sa migration) et un effectif où certains joueurs
  # l'ont et d'autres pas ferait lever `ArgumentError: comparison of Array with
  # Array failed` à `sort_by` — `nil <=> 1` vaut nil. Un nil se comporte donc comme
  # un 0, c'est-à-dire « tiré en premier », plutôt que de casser le classement.
  def rank_key(tu)
    [-tu.ranking_points, -tu.point_average, -tu.set_average, tu.losses, tu.draw_order.to_i]
  end

  # Vrai si `user` organise le tournoi : soit l'admin/créateur, soit un co-organisateur.
  # (Sert aux droits de gestion du tableau à partir du Lot 3.)
  def organizer?(user)
    return false if user.blank?

    user_id == user.id || tournament_users.any? { |tu| tu.user_id == user.id && tu.co_organizer? }
  end

  # Résumé lisible de la structure PRÉVUE, calculé depuis le format, l'effectif
  # attendu (max_players) et les réglages de l'organisateur — donc juste même quand
  # il personnalise la taille des poules ou du tableau final, et valable pour
  # n'importe quel effectif (mode « Libre » compris).
  # Le miroir côté client vit dans tournament_form_controller.js (_structureText).
  def structure_summary
    return nil if format.blank? || max_players.blank?

    case format
    when "poules"
      "#{planned_pool_count} poules de #{pool_size} + #{planned_bracket_stage}"
    when "criterium_federal"
      criterium_structure_summary
    when "ronde_suisse"
      "Ronde suisse (#{wins_to_qualify} V / #{losses_to_eliminate} D) + #{planned_bracket_stage}"
    else # championnat
      base = "#{max_players} joueurs, #{max_players - 1} journées"
      playoffs? ? "#{base}, top #{planned_final_size} en playoffs" : "#{base}, vainqueur = 1er du classement"
    end
  end

  # Structure prévue AVANT le lancement : les mêmes règles que #pool_count /
  # #final_size mais basées sur l'effectif ATTENDU (max_players) et non sur les
  # inscrits du moment — un tournoi vide doit déjà annoncer sa structure.
  def planned_pool_count
    [pool_plan(max_players).size, 1].max
  end

  def planned_final_size
    return bracket_size if bracket_size.present?
    # Classement intégral : le tableau accueille tout l'effectif, pas 2 par poule.
    return bracket_capacity_for(max_players.to_i) if criterium? && criterium_mode(max_players) == :integral
    return bracket_capacity_for(planned_pool_count * 2) if POOL_BASED_FORMATS.include?(format)

    max_players.to_i <= 8 ? 4 : 8
  end

  # Arrondit un nombre de qualifiés à la puissance de 2 immédiatement supérieure :
  # un tableau à élimination directe ne peut avoir que 2, 4, 8, 16… places (les
  # places excédentaires sont des byes, cf. BracketBuilder). Ex. 3 poules → 6
  # qualifiés → tableau de 8. Garantit que la valeur recommandée respecte la même
  # contrainte que celle qu'on impose à un réglage manuel (bracket_size).
  def bracket_capacity_for(qualified_count)
    size = 2
    size *= 2 while size < qualified_count
    size
  end

  # Tour d'entrée du tableau final prévu ("quarts", "demi-finales"…).
  def planned_bracket_stage
    size = planned_final_size
    BRACKET_STAGE_NAMES[size] || "tableau à #{size}"
  end

  # ── Ronde Suisse + tableau final (Lot 3) ─────────────────────────────────────

  # Rondes de la phase suisse, dans l'ordre.
  def swiss_rounds   = tournament_rounds.swiss.ordered
  # Journées de championnat (round-robin intégral), dans l'ordre.
  def league_rounds  = tournament_rounds.league.ordered
  # Journées de poules (round-robin par poule), dans l'ordre.
  def pool_rounds    = tournament_rounds.pool.ordered

  # Tours du tableau final (« OK »), dans l'ordre.
  #
  # `main_branch` est un GARDE-FOU, pas une précaution de style : #champion lit
  # `bracket_rounds.last.tournament_matches.first.winner`. Si un mini-tableau de
  # classement atterrissait ici, le champion du tournoi serait le vainqueur du
  # match pour la 7e place. Les mini-tableaux vivent en phase "classification",
  # donc hors de ce scope de deux façons — ceinture et bretelles.
  def bracket_rounds = tournament_rounds.bracket.main_branch.ordered
  # Le tableau final a-t-il déjà commencé ?
  def bracket_started? = tournament_rounds.bracket.exists?

  # ── Critérium Fédéral (FFTT) ────────────────────────────────────────────────
  def criterium? = format == "criterium_federal"

  # Classement de chaque poule au règlement FFTT : { index_poule => PoolStandings }.
  #
  # Memoïsé ET requête unique : les matchs de poule sont chargés une seule fois puis
  # injectés dans chaque PoolStandings, sinon classer 8 poules coûterait 8 requêtes.
  # Source unique partagée par les vues (onglet Classement) et par CriteriumFlow,
  # qui décide des barrages et du tableau final — les deux doivent voir le MÊME
  # classement, sans quoi l'affichage contredirait les appariements.
  # Invalide les classements memoïsés. À appeler par tout code qui MODIFIE des
  # résultats de poule avant de relire un classement sur la même instance.
  #
  # Sans cela, une correction de score suivie d'une régénération de la phase finale
  # peut mélanger deux états : les barrages reconstruits depuis le classement neuf,
  # le tableau final depuis le memo périmé. Un joueur redescendu 2e y figurerait
  # alors DEUX fois — comme 1er de poule (memo) et comme vainqueur de barrage
  # (état réel). Le tableau compterait un joueur en double et un autre en moins.
  def reset_standings!
    @pool_standings = nil
    @standings = nil
    self
  end

  def pool_standings
    @pool_standings ||= begin
      matches = TournamentMatch.joins(:tournament_round)
                               .where(tournament_rounds: { tournament_id: id, phase: "pool" })
                               .to_a
      pools.sort.to_h { |index, members| [index, PoolStandings.new(self, members, matches: matches)] }
    end
  end

  # Position (1-based) d'un joueur dans sa poule, ou nil s'il n'est pas en poule.
  def pool_position_of(tournament_user)
    return nil if tournament_user.pool.blank?

    pool_standings[tournament_user.pool]&.place_of(tournament_user)
  end

  # Topologie déclarée du Critérium (barrages, tableau final, consolante, matchs de
  # classement) — cf. CriteriumStructure. On compte les poules RÉELLEMENT
  # constituées quand elles le sont : un abandon ferait varier `pool_count` (dérivé
  # de l'effectif) et donc la structure en cours de tournoi.
  def criterium_structure
    @criterium_structure ||= CriteriumStructure.new(
      pool_count: pools.presence&.size || pool_count,
      players_per_pool: pool_size,
      mode: criterium_mode,
      player_count: approved_players_count
    )
  end

  # Tours des barrages / de la consolante / des mini-tableaux de classement.
  def barrage_rounds        = tournament_rounds.barrage.ordered
  def consolation_rounds    = tournament_rounds.consolation.main_branch.ordered
  def classification_rounds = tournament_rounds.classification.order(:branch, :number)

  # La phase finale a-t-elle commencé ? Plus large que #bracket_started? : le
  # Critérium démarre par les BARRAGES, avant que le tableau final n'existe.
  def final_phase_started? = tournament_rounds.final_phase.exists?

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
    # Critérium à poule unique (≤ 7 joueurs) : le classement de la poule tranche,
    # il n'y a aucun tableau — pas même une structure à préfigurer.
    return false if criterium_pools_only?

    format != "championnat" || playoffs?
  end

  # Ce tournoi aura-t-il des barrages ? Même intention que #bracket_expected? : la
  # phase s'affiche dès le lancement, avec des cases « À déterminer », plutôt
  # qu'après la dernière journée de poule — l'organisateur voit d'emblée ce qui
  # l'attend, et la pastille de navigation ne surgit pas en cours de route.
  #
  # La question se pose à la STRUCTURE, seule à savoir si le format en prévoit :
  # le mode intégral (effectif réduit) envoie tout le monde dans un tableau unique
  # sans barrage, et un Critérium à poule unique n'a aucune phase finale.
  def barrage_expected? = criterium? && criterium_structure.node("barrage").present?

  # Nombre de barrages à jouer : les 2es contre les 3es de poule, donc une
  # rencontre par poule. Lu sur la structure et non recalculé ici, pour que la
  # préfiguration ne puisse pas diverger de ce que CriteriumFlow créera.
  def expected_barrage_count
    node = criterium_structure.node("barrage")
    node ? node.entrants / 2 : 0
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
  # En Critérium Fédéral, on passe par le classement final : le dernier tour du
  # tableau final n'est pas forcément le dernier tour JOUÉ du tournoi (la
  # consolante et les matchs de classement continuent après la finale), et un
  # tournoi terminé à la main peut n'avoir aucune finale.
  def champion
    return nil unless completed?
    return standings.champion if criterium?
    return bracket_rounds.last&.tournament_matches&.first&.winner if bracket_started?

    ranked_players.first if format == "championnat"
  end

  # Classement final dérivé des matchs (places jouées, ex æquo, compaction) —
  # cf. TournamentStandings. Memoïsé : lu par #champion, l'onglet Classement et
  # la bannière du vainqueur, qui doivent tous afficher le même classement.
  def standings = @standings ||= TournamentStandings.new(self)

  # Ronde en cours. Le tableau final (bracket) est prioritaire ; sinon la première
  # ronde NON TERMINÉE de la phase round-robin du format (un tournoi n'emploie
  # qu'UNE phase round-robin : swiss OU league OU pool), à défaut la dernière.
  #
  # « La première non terminée » et non « la dernière générée » : en poules, tout le
  # calendrier est créé au lancement (cf. PoolBuilder) et les rencontres ne se
  # jouent plus dans l'ordre — la dernière journée existe dès le départ et
  # désignerait une ronde à laquelle personne n'a encore touché. Pour la ronde
  # suisse et le championnat, qui génèrent toujours un tour à la fois, les deux
  # définitions coïncident.
  def current_round
    bracket_rounds.last || begin
      rounds = tournament_rounds.where(phase: %w[swiss league pool]).ordered.to_a
      rounds.find { |round| !round.complete? } || rounds.last
    end
  end

  # Regroupement des joueurs par poule (Lot 5, format "poules").
  # Clé = index de poule (0-based) ; valeur = joueurs de la poule.
  def pools
    approved_players.select { |tu| tu.pool.present? }.group_by(&:pool)
  end

  # ── Structure : réglages recommandés, personnalisables (Lot 7) ───────────────
  # Les 4 méthodes ci-dessous sont la SEULE source de vérité de la structure, lue
  # par tous les moteurs (PoolBuilder, SwissPairing, BracketBuilder). Chacune
  # renvoie le réglage choisi par l'organisateur s'il en a saisi un, sinon la
  # valeur recommandée — historiquement la seule possible.
  #
  # Les colonnes portent un nom différent des méthodes (players_per_pool vs
  # #pool_size…) précisément pour que ces méthodes ne masquent aucun attribut :
  # `players_per_pool` reste la valeur brute (nil = « recommandé »), lisible telle
  # quelle par le formulaire.

  # Joueurs par poule (format "poules").
  DEFAULT_POOL_SIZE = 4

  # Taille de poule. En Critérium sans réglage explicite, c'est le PLAN de poules
  # qui décide (les seuils du règlement), donc la plus grande poule prévue : c'est
  # elle qui détermine jusqu'à quel rang un joueur peut sortir de sa poule, donc
  # combien de rangs CriteriumStructure doit savoir faire entrer en phase finale.
  def pool_size
    return players_per_pool if players_per_pool.present?
    return pool_plan.max || DEFAULT_POOL_SIZE if criterium?

    DEFAULT_POOL_SIZE
  end

  # Nombre de poules, déduit de l'effectif et de la taille de poule voulue —
  # réutilisé par PoolBuilder pour la répartition ET ici pour dimensionner le
  # tableau final (cf. #final_size).
  def pool_count
    return [pool_plan.size, 1].max if criterium?

    [(approved_players_count / pool_size.to_f).ceil, 1].max
  end

  # ── Plan de poules (Lot 6) ──────────────────────────────────────────────────
  # La taille de CHAQUE poule, décroissante : 11 joueurs → [4, 4, 3].
  #
  # C'est une DESCRIPTION, pas la répartition : c'est PoolBuilder#assign_pools! qui
  # affecte les joueurs, en serpentin. Les deux concordent par construction — un
  # serpentin sur n colonnes donne à chaque poule ⌈effectif/n⌉ ou ⌊effectif/n⌋
  # joueurs, soit exactement le même multi-ensemble de tailles que #balanced_plan.
  # Seul l'ordre des poules peut différer, et il n'a aucune signification.
  #
  # `count` est paramétrable pour pouvoir annoncer la structure PRÉVUE depuis
  # `max_players`, avant que quiconque soit inscrit (cf. #structure_summary).
  def pool_plan(count = approved_players_count)
    count = count.to_i
    return [] if count < 1

    balanced_plan(count, planned_pool_count_for(count))
  end

  # Variante de phase finale effectivement appliquée (cf. CRITERIUM_MODES).
  # Le réglage explicite gagne ; sinon, ce sont les seuils d'effectif du règlement.
  def criterium_mode(count = approved_players_count)
    return final_phase_mode.to_sym if final_phase_mode.present?

    count = count.to_i
    return :none if count <= CRITERIUM_POOLS_ONLY_MAX
    return :integral if count <= CRITERIUM_INTEGRAL_MAX

    :standard
  end

  # ── Constitution des poules (Lot 7) ─────────────────────────────────────────
  # Mêmes conventions que les autres réglages : la colonne garde la valeur brute
  # (nil = défaut), la méthode donne la valeur effective. Les noms diffèrent
  # exprès de ceux des colonnes pour ne masquer aucun attribut.
  def seeding_mode = pool_seeding_mode.presence || POOL_SEEDING_MODES.first
  def seeded_pots? = seeding_mode == "pots"
  def pot_count    = seeded_pot_count.presence || DEFAULT_POT_COUNT

  # Inscrits regroupés par chapeau — clé `nil` = chapeau général. Lu par le
  # panneau de constitution pour afficher le remplissage réel.
  def pots = approved_players.group_by(&:pot)

  # Tableau unique à classement intégral : chaque place est jouée, aucun ex æquo.
  def criterium_integral? = criterium? && criterium_mode == :integral

  # Poule unique sans phase finale : le classement final EST celui de la poule.
  def criterium_pools_only? = criterium? && criterium_mode == :none

  # Taille du tableau final. Réglage explicite (bracket_size) sinon, selon le format :
  #   - poules : le double du nombre de poules — les 2 premiers de chaque poule
  #     (règle classique, ex. Coupe du monde) : 2 poules de 4 → demi-finales (4),
  #     4 poules → quarts (8), 8 poules → huitièmes (16).
  #   - ronde suisse / championnat : Final 4 pour un petit tournoi (≤ 8 joueurs),
  #     Final 8 au-delà (plafond volontaire — contrairement aux poules, ne grandit
  #     pas avec l'effectif au-delà de 8).
  def final_size
    bracket_size.presence || recommended_final_size
  end

  # Le Critérium suit la même règle que les poules — et pour cause : ses entrants
  # sont exactement les n 1ers de poule + les n vainqueurs de barrage, soit 2n.
  #
  # Sauf en classement intégral : là, il n'y a pas de sortants de poule, TOUT LE
  # MONDE entre dans le tableau unique. Le dimensionner sur 2n y couperait le
  # tournoi en deux (à 16 joueurs, un tableau de 8 pour 16 entrants).
  def recommended_final_size
    return bracket_capacity_for(approved_players_count) if criterium_integral?
    return bracket_capacity_for(pool_count * 2) if POOL_BASED_FORMATS.include?(format)

    approved_players_count <= 8 ? 4 : 8
  end

  # Ronde suisse : seuils de qualification / élimination (bilan V-D).
  def wins_to_qualify = swiss_wins_to_qualify.presence || TournamentUser::WINS_TO_QUALIFY

  def losses_to_eliminate = swiss_losses_to_eliminate.presence || TournamentUser::LOSSES_TO_ELIMINATE

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

  # Cf. le before_destroy en tête de classe : les matchs référencent les inscrits,
  # ils doivent donc disparaître avant eux.
  def destroy_rounds_before_players
    tournament_rounds.destroy_all
  end

  # ── Plan de poules : les seuils d'effectif du règlement ─────────────────────
  # Un réglage explicite de l'organisateur gagne toujours. Sinon, en Critérium,
  # ce sont les seuils du règlement FFTT ; ailleurs, la règle générique.
  def planned_pool_count_for(count)
    size = players_per_pool.presence
    return [(count / size.to_f).ceil, 1].max if size
    return criterium_pool_count_for(count) if criterium?

    [(count / DEFAULT_POOL_SIZE.to_f).ceil, 1].max
  end

  # Les seuils du document de référence. Volontairement écrits en clair plutôt que
  # dérivés d'une formule : ce sont des paliers arbitraires du règlement, une
  # formule les rendrait plus difficiles à confronter au texte.
  def criterium_pool_count_for(count)
    return 1 if count <= CRITERIUM_POOLS_ONLY_MAX
    return 2 if count <= 10
    return 3 if count == 11
    return 4 if count <= CRITERIUM_INTEGRAL_MAX

    [(count / DEFAULT_POOL_SIZE.to_f).ceil, 1].max
  end

  # Répartit `count` joueurs en `pools` poules aussi égales que possible, les plus
  # grandes d'abord : 11 en 3 poules → [4, 4, 3].
  def balanced_plan(count, pools)
    base, extra = count.divmod(pools)
    Array.new(pools) { |index| base + (index < extra ? 1 : 0) }
  end

  # Résumé de structure du Critérium, une phrase par variante (cf. CRITERIUM_MODES).
  # Miroir client : tournament_form_controller.js#_criteriumText.
  def criterium_structure_summary
    plan = pool_plan(max_players)

    case criterium_mode(max_players)
    when :none
      "Poule unique de #{plan.first}, classement final = classement de poule"
    when :integral
      # Pas de nom de tour d'entrée ici : « huitièmes » désignerait le tour où
      # entrent les QUALIFIÉS, alors qu'en intégral le tableau accueille tout
      # l'effectif et fait jouer chaque place jusqu'à la dernière.
      "#{pool_plan_label(plan)} + tableau unique de #{planned_final_size}, chaque place jouée"
    else
      "#{pool_plan_label(plan)}, barrages, #{planned_bracket_stage} + consolante"
    end
  end

  # « 4 poules de 4 » quand elles sont égales, « 3 poules (4-4-3) » sinon : à
  # effectif non divisible, annoncer une taille unique serait faux.
  def pool_plan_label(plan)
    return "#{plan.size} poules de #{plan.first}" if plan.uniq.size == 1

    "#{plan.size} poules (#{plan.join('-')})"
  end

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

  # Puissance de 2 : 4 & 3 == 0, 8 & 7 == 0… (un seul bit à 1 en binaire).
  def bracket_size_is_power_of_two
    return if bracket_size.blank? || bracket_size < 2
    return if bracket_size.nobits?(bracket_size - 1)

    errors.add(:bracket_size, "doit être une puissance de 2 (4, 8, 16, 32…)")
  end

  # Poules de 3 ou 4 en Critérium Fédéral (cf. CriteriumStructure). Vide reste
  # autorisé : c'est le mode « recommandé », où #pool_plan choisit la taille.
  def criterium_pool_size_is_three_or_four
    return unless criterium?
    return if players_per_pool.blank? || [3, 4].include?(players_per_pool)

    errors.add(:players_per_pool, "doit être 3 ou 4 pour un Critérium Fédéral")
  end
end
