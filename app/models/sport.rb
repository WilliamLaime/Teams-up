# Modèle Sport — représente un sport (Football, Tennis, Padel, etc.)
# Champs :
#   name : nom affiché (ex: "Football")
#   icon : emoji du sport (ex: "⚽")
#   slug : identifiant URL-friendly (ex: "football")
class Sport < ApplicationRecord
  # Un sport peut être pratiqué par plusieurs utilisateurs via la table user_sports
  has_many :user_sports, dependent: :destroy
  has_many :users, through: :user_sports

  # Un sport peut avoir plusieurs matchs associés
  has_many :matches, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :icon, presence: true

  # Formats disponibles pour ce sport
  # Chaque format = { label: "5v5", players: 9 }
  # players = joueurs manquants (organisateur déjà compté)
  # players: nil → format Libre (taille libre, sans contrainte de max)
  def available_formats
    libre = { label: "Libre", players: nil }
    case slug
    when "football"   then [{ label: "5v5",  players: 9  }, { label: "11v11", players: 21 }, libre]
    when "tennis"     then [{ label: "1v1",  players: 1  }, { label: "2v2", players: 3 }, libre]
    when "padel"      then [{ label: "2v2",  players: 3  }, libre]
    when "volleyball" then [{ label: "3v3",  players: 5  }, { label: "6v6", players: 11 }, libre]
    when "basketball" then [{ label: "1v1", players: 1 }, { label: "2v2", players: 3 }, { label: "3v3", players: 5 },
                            { label: "5v5", players: 9 }, libre]
    when "handball"   then [{ label: "6v6",  players: 11 }, libre]
    when "badminton"  then [{ label: "1v1",  players: 1  }, { label: "2v2", players: 3 }, libre]
    when "ping-pong"  then [{ label: "1v1",  players: 1  }, { label: "2v2", players: 3 }, libre]
    else                   [libre]
    end
  end

  # Grille de niveaux spécifique à chaque sport
  # Chaque niveau = { label: "Nom affiché", ref: "Référence officielle (optionnel)" }
  # La ref est affichée dans la modale explicative pour les sports avec classement officiel
  def available_levels
    case slug
    when "football", "basketball", "handball", "volleyball"
      # Sports collectifs : échelle généraliste 5 niveaux
      [
        { label: "Débutant" },
        { label: "Amateur" },
        { label: "Intermédiaire" },
        { label: "Confirmé" },
        { label: "Expert" }
      ]
    when "padel"
      # Grille officielle FFP (Fédération Française de Padel) — 7 niveaux
      [
        { label: "Débutant",         ref: "NC",
          desc: "Découverte du padel. Apprentissage des coups de base (coup droit, revers, lob). Pas encore de compétition officielle." },
        { label: "Perfectionnement", ref: "P12-P25",
          desc: "Échanges réguliers acquis, jeu surtout défensif depuis le fond. Premiers tournois, résultats encore irréguliers." },
        { label: "Élémentaire",      ref: "P100",
          desc: "Jeu de fond maîtrisé, début de placement tactique. Participe à des tournois locaux et commence à jouer au filet." },
        { label: "Intermédiaire",    ref: "P250",
          desc: "Maîtrise le jeu au filet et le fond de court. Échanges variés, tactique de base acquise. Compétitions régulières en club." },
        { label: "Confirmé",         ref: "P500",
          desc: "Technique solide sur tous les coups, jeu tactique développé (bandeja, vibora). Compétitions régionales." },
        { label: "Avancé",           ref: "P1000",
          desc: "Haut niveau amateur, jeu rapide et précis, lecture du jeu avancée. Championnats régionaux et interrégionaux." },
        { label: "Expert",           ref: "P2000+",
          desc: "Joueur élite, maîtrise complète à haute vitesse et intensité. Compétitions nationales et internationales." }
      ]
    when "tennis"
      # Grille officielle FFT (Fédération Française de Tennis) — 6 niveaux
      [
        { label: "Débutant",      ref: "NC – balle verte",
          desc: "Apprentissage des coups de base (coup droit, revers, service). Premiers échanges sur formats adaptés avec balle rouge, orange ou verte." },
        { label: "Élémentaire",   ref: "Balle jaune, 1ers tournois",
          desc: "Joue sur format traditionnel (balle jaune). Accélère avec son coup fort, participe aux premiers tournois TMC en simple ou double." },
        { label: "Intermédiaire", ref: "Séries 30",
          desc: "Utilise les effets au fond et au service. Tient l'échange dans la durée ou attaque sur balles courtes. Compétitions en club." },
        { label: "Confirmé",      ref: "15/5 – 15/3",
          desc: "Maîtrise son jeu à vitesse moyenne. Au moins une solution par situation. Gagne des matchs face aux joueurs de 3e série." },
        { label: "Avancé",        ref: "15/2 – 1/6",
          desc: "Maîtrise complète à vitesse élevée. Choisit les zones, trajectoires et rythmes selon son intention. Compétitions régionales." },
        { label: "Expert",        ref: "0 et +",
          desc: "Jeu à haute vitesse et intensité dans la durée. Compétitions régionales, nationales et internationales. Circuits ITF/ATP/WTA." }
      ]
    when "badminton"
      # Grille officielle FFBad (Fédération Française de Badminton) — 5 niveaux
      [
        { label: "Débutant",      ref: "NC",
          desc: "Découverte du badminton. Apprentissage des coups de base (dégagement, smash, filet). Jeux entre débutants." },
        { label: "Initié",        ref: "Série D",
          desc: "Maîtrise des frappes basiques, échanges réguliers. Premiers matchs compétitifs, service et déplacements acquis." },
        { label: "Intermédiaire", ref: "Série C",
          desc: "Joue régulièrement en compétition. Maîtrise le jeu au fond et au filet, tactique de base développée." },
        { label: "Confirmé",      ref: "Série B",
          desc: "Bon niveau technique, placement tactique maîtrisé, échanges rapides. Compétitions régionales et interclubs." },
        { label: "Expert",        ref: "Série A+",
          desc: "Haut niveau, jeu rapide et complet, lecture du jeu avancée. Compétitions nationales et championnats de France." }
      ]
    else
      # Fallback générique pour tout sport non encore configuré
      [
        { label: "Débutant" },
        { label: "Intermédiaire" },
        { label: "Avancé" }
      ]
    end
  end

  # Formats de TOURNOI compatibles avec ce sport (≠ available_formats qui gère
  # les tailles d'équipe d'un match). Principe : les sports de raquette se jouent
  # en ronde suisse / poules ; les sports collectifs en championnat / poules.
  # Renvoie un array de valeurs de Tournament::FORMATS.
  # Le Critérium Fédéral est réservé au tennis de table : c'est le règlement de la
  # FFTT (barème points-parties 2/1, barrages, consolante, matchs de classement),
  # il n'a pas de sens pour les autres sports.
  def available_tournament_formats
    case slug
    when "ping-pong"
      %w[ronde_suisse poules criterium_federal]
    when "tennis", "padel", "badminton"
      %w[ronde_suisse poules]
    when "football", "basketball", "handball", "volleyball"
      %w[championnat poules]
    else
      Tournament::FORMATS
    end
  end

  # Règles de score d'un match de tournoi pour ce sport (Lot 4, étendu Lot 6). Renvoie
  # un Hash dont la clé `mode` pilote la saisie :
  #   :sets  (sports de raquette) — score set par set, jamais de nul :
  #     best_of    : nombre de sets « au meilleur de » (3 → il faut en gagner 2)
  #     target     : score à atteindre pour remporter un set (jeux au tennis, points ailleurs)
  #     win_by_two : faut-il 2 d'écart pour conclure un set (règle du ping-pong / badminton)
  #     cap        : plafond au-delà duquel 1 point d'écart suffit (tie-break) ; nil = pas de plafond
  #     final_best_of : best_of RENFORCÉ en phase finale (tableau à élimination directe),
  #       comme le veut le règlement du tennis de table : 3 sets gagnants en poule /
  #       ronde suisse, 4 en phase finale. Absent = mêmes règles à toutes les phases.
  #       Appliqué par TournamentMatch#scoring_rules, seul endroit qui connaît la phase.
  #   :score (sports collectifs) — un seul score final saisi :
  #     allow_draw : le nul est-il un résultat possible pour ce sport
  # Le fallback (sports sans configuration) reste jouable au meilleur des 3 sets.
  def scoring_rules
    case slug
    when "tennis", "padel" then { mode: :sets, best_of: 3, target: 6,  win_by_two: true, cap: 7,   allow_draw: false }
    when "badminton"       then { mode: :sets, best_of: 3, target: 21, win_by_two: true, cap: 30,  allow_draw: false }
    when "ping-pong"       then { mode: :sets, best_of: 5, target: 11, win_by_two: true, cap: nil, allow_draw: false, final_best_of: 7 }
    when "volleyball"      then { mode: :sets, best_of: 5, target: 25, win_by_two: true, cap: nil, allow_draw: false }
    when "football", "handball" then { mode: :score, allow_draw: true }
    when "basketball"           then { mode: :score, allow_draw: false }
    else { mode: :sets, best_of: 3, target: 6, win_by_two: false, cap: nil, allow_draw: false }
    end
  end

  # Barème de points de classement V/N/D pour le championnat/poules (Lot 6). nil pour
  # les sports de raquette (ronde suisse / poules) : ils n'ont pas de barème dédié,
  # cf. TournamentUser#ranking_points qui retombe alors sur 1 point par victoire.
  # Table de correspondance plutôt qu'un case/when : quatre branches qui ne font que
  # renvoyer une valeur constante se lisent mieux alignées (et rubocop le signale via
  # Style/HashLikeCase). Gelée car partagée entre tous les appels — aucun appelant ne
  # la mute : ils font `.merge`, `.dig` ou une lecture simple.
  RANKING_POINTS_RULES = {
    "football" => { win: 3, draw: 1, loss: 0 }.freeze, # barème FIFA en vigueur
    "handball" => { win: 2, draw: 1, loss: 0 }.freeze, # barème IHF historique
    "basketball" => { win: 1, draw: 0, loss: 0 }.freeze, # pas de nul possible
    "volleyball" => { win: 1, draw: 0, loss: 0 }.freeze # pas de nul possible
  }.freeze

  def ranking_points_rules
    RANKING_POINTS_RULES[slug]
  end

  # Barème « points-parties » d'une phase de POULES, lu UNIQUEMENT par PoolStandings.
  #
  # Le tennis de table compte 2 points par victoire et 1 par défaite jouée (règlement
  # FFTT du Critérium Fédéral) — un forfait ne rapporte rien.
  #
  # Volontairement séparé de #ranking_points_rules, qui alimente
  # TournamentUser#ranking_points → Tournament#rank_key → le seeding de TOUS les
  # formats. Y injecter le 2/1 serait une régression silencieuse sur la ronde suisse :
  # l'équivalence « 2 V / 1 D ≡ ordre par victoires » ne vaut qu'à nombre de matchs
  # ÉGAL, ce que la ronde suisse ne garantit pas (bye, abandon, entrée tardive). Un
  # joueur à 1 V - 0 D (2 pts) se retrouverait à égalité avec un 0 V - 2 D (2 pts),
  # alors qu'aujourd'hui la victoire tranche.
  def pool_points_rules
    case slug
    when "ping-pong" then { win: 2, draw: 0, loss: 1, forfeit: 0 }
    else (ranking_points_rules || { win: 1, draw: 0, loss: 0 }).merge(forfeit: 0)
    end
  end

  # Nombre de joueurs par défaut = premier format du sport (garde-fou si nil)
  def default_player_count
    available_formats.first[:players] || 1
  end

  # Max de joueurs = plus grand format du sport (compact exclut le nil du format Libre)
  def max_player_count
    available_formats.map { |f| f[:players] }.compact.max
  end
end
