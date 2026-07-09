# Ce fichier contient uniquement les données de référence nécessaires au
# fonctionnement de l'application dans tous les environnements.
# Idempotent : peut être relancé sans créer de doublons.

# ─── ACHIEVEMENTS ─────────────────────────────────────────────────────────────

puts "Création des achievements..."

achievements_data = [
  # ── Catégorie MATCH ──────────────────────────────────────────────────────────
  {
    key:         "first_join",
    name:        "Premier pas sur le terrain",
    description: "Rejoins ton premier match",
    xp_reward:   50,
    icon_emoji:  "⚽",
    category:    "match"
  },
  {
    key:         "matches_5",
    name:        "Habitué du terrain",
    description: "Participe à 5 matchs",
    xp_reward:   150,
    icon_emoji:  "🔥",
    category:    "match"
  },
  {
    key:         "matches_10",
    name:        "Vétéran",
    description: "Participe à 10 matchs",
    xp_reward:   300,
    icon_emoji:  "🌟",
    category:    "match"
  },
  {
    key:         "first_match_created",
    name:        "Organisateur en herbe",
    description: "Crée ton premier match",
    xp_reward:   100,
    icon_emoji:  "🏟️",
    category:    "match"
  },
  {
    key:         "organized_3",
    name:        "Chef d'équipe",
    description: "Organise 3 matchs",
    xp_reward:   200,
    icon_emoji:  "🎯",
    category:    "match"
  },
  {
    key:         "matches_25",
    name:        "Légende du terrain",
    description: "Participe à 25 matchs",
    xp_reward:   500,
    icon_emoji:  "🏆",
    category:    "match"
  },
  {
    key:         "matches_50",
    name:        "Roi des terrains",
    description: "Participe à 50 matchs",
    xp_reward:   1000,
    icon_emoji:  "👑",
    category:    "match"
  },
  {
    key:         "matches_75",
    name:        "Indestructible",
    description: "Participe à 75 matchs",
    xp_reward:   750,
    icon_emoji:  "🛡️",
    category:    "match"
  },
  {
    key:         "matches_100",
    name:        "Centurion",
    description: "Participe à 100 matchs",
    xp_reward:   1500,
    icon_emoji:  "🥇",
    category:    "match"
  },
  {
    key:         "organized_10",
    name:        "Général des terrains",
    description: "Organise 10 matchs",
    xp_reward:   400,
    icon_emoji:  "🎖️",
    category:    "match"
  },
  {
    key:         "organized_25",
    name:        "Directeur sportif",
    description: "Organise 25 matchs",
    xp_reward:   700,
    icon_emoji:  "📋",
    category:    "match"
  },
  {
    key:         "hat_trick",
    name:        "Hat-trick",
    description: "Rejoins 3 matchs en 7 jours",
    xp_reward:   125,
    icon_emoji:  "⚡",
    category:    "match"
  },
  {
    key:         "night_owl",
    name:        "Joueur nocturne",
    description: "Participe à un match après 20h",
    xp_reward:   80,
    icon_emoji:  "🌙",
    category:    "match"
  },
  {
    key:         "sport_explorer",
    name:        "Touche-à-tout",
    description: "Pratique 3 sports différents",
    xp_reward:   200,
    icon_emoji:  "🎽",
    category:    "match"
  },
  {
    key:         "early_bird",
    name:        "Lève-tôt",
    description: "Participe à un match avant 9h",
    xp_reward:   80,
    icon_emoji:  "🌅",
    category:    "match"
  },
  {
    key:         "comeback",
    name:        "Revenant",
    description: "Reviens jouer après 30 jours d'absence",
    xp_reward:   100,
    icon_emoji:  "🔄",
    category:    "match"
  },

  # ── Catégorie SOCIAL ─────────────────────────────────────────────────────────
  {
    key:         "first_message",
    name:        "Première prise de parole",
    description: "Envoie ton premier message dans un chat",
    xp_reward:   25,
    icon_emoji:  "💬",
    category:    "social"
  },
  {
    key:         "messages_10",
    name:        "Grande gueule",
    description: "Envoie 10 messages au total",
    xp_reward:   100,
    icon_emoji:  "🗣️",
    category:    "social"
  },
  {
    key:         "messages_50",
    name:        "Voix du stade",
    description: "Envoie 50 messages au total",
    xp_reward:   250,
    icon_emoji:  "📢",
    category:    "social"
  },
  {
    key:         "messages_100",
    name:        "DJ du vestiaire",
    description: "Envoie 100 messages au total",
    xp_reward:   350,
    icon_emoji:  "🎙️",
    category:    "social"
  },
  {
    key:         "messages_250",
    name:        "Inarrêtable",
    description: "Envoie 250 messages au total",
    xp_reward:   600,
    icon_emoji:  "💥",
    category:    "social"
  },
  {
    key:         "first_review",
    name:        "Juge de touche",
    description: "Laisse ton premier avis sur un joueur",
    xp_reward:   40,
    icon_emoji:  "🌟",
    category:    "social"
  },
  {
    key:         "reviews_5",
    name:        "Arbitre confirmé",
    description: "Laisse 5 avis sur des joueurs",
    xp_reward:   120,
    icon_emoji:  "⚖️",
    category:    "social"
  },

  # ── Catégorie PROFIL ─────────────────────────────────────────────────────────
  {
    key:         "profile_complete",
    name:        "Identité complète",
    description: "Complète ton profil (avatar, description et téléphone)",
    xp_reward:   75,
    icon_emoji:  "👤",
    category:    "profile"
  },
  {
    key:         "avatar_added",
    name:        "Visage révélé",
    description: "Ajoute une photo de profil",
    xp_reward:   50,
    icon_emoji:  "📸",
    category:    "profile"
  },
  {
    key:         "description_written",
    name:        "Ma story",
    description: "Rédige ta description de profil",
    xp_reward:   30,
    icon_emoji:  "✍️",
    category:    "profile"
  },
  {
    key:         "phone_added",
    name:        "Joignable",
    description: "Ajoute ton numéro de téléphone",
    xp_reward:   25,
    icon_emoji:  "📱",
    category:    "profile"
  },
  {
    key:         "location_added",
    name:        "Localisé",
    description: "Renseigne ta ville",
    xp_reward:   25,
    icon_emoji:  "📍",
    category:    "profile"
  },
  {
    key:         "achievement_collector",
    name:        "Collectionneur",
    description: "Débloque 10 achievements",
    xp_reward:   400,
    icon_emoji:  "💎",
    category:    "profile"
  },
  {
    key:         "og_player",
    name:        "OG",
    description: "Membre depuis plus d'un an",
    xp_reward:   300,
    icon_emoji:  "🎂",
    category:    "profile"
  }
]

achievements_data.each do |data|
  Achievement.find_or_create_by!(key: data[:key]) do |a|
    a.name        = data[:name]
    a.description = data[:description]
    a.xp_reward   = data[:xp_reward]
    a.icon_emoji  = data[:icon_emoji]
    a.category    = data[:category]
  end
end

puts "✅ #{Achievement.count} achievements en base."

# ─── SPORTS ───────────────────────────────────────────────────────────────────

puts "Création des sports..."

# Source unique de vérité pour la liste des sports (cf. db/sports.rb).
# Le même fichier est rejoué à chaque déploiement via `rails db:seed_sports`.
load Rails.root.join("db", "sports.rb")
seed_sports

# ─── TOURNOIS (démo) ──────────────────────────────────────────────────────────
# Jeu de données couvrant les 3 sections de la page liste (/tournois) :
#   1. Mes tournois en cours    → 1er user inscrit + statut in_progress
#   2. Tournois à rejoindre      → statut open, deadline future, non inscrit
#   3. Tournois en cours publics → statut in_progress, non inscrit
# Idempotent : find_or_create_by sur le nom.

puts "Création des tournois de démo..."

creator = User.first

if creator.nil?
  puts "⚠️  Aucun utilisateur en base — tournois de démo ignorés."
else
  football = Sport.find_by(slug: "football")
  padel    = Sport.find_by(slug: "padel")
  tennis   = Sport.find_by(slug: "tennis")

  demo_tournaments = [
    { name: "Open Riviera Winter", sport: padel, format: "ronde_suisse", max_players: 16,
      place: "Club Padel Riviera", status: "in_progress", registered: true,
      date: Date.current + 2, deadline: 1.day.ago,
      description: "Le rendez-vous hivernal du padel sur la Riviera." },

    { name: "Ligue Urbaine Paris", sport: football, format: "championnat", max_players: 32,
      place: "Five Paris 18", status: "open", registered: false,
      date: Date.current + 20, deadline: Date.current + 10,
      description: "Championnat urbain, tout le monde s'affronte, les 8 premiers en playoffs." },

    { name: "Tournoi d'Automne P100", sport: padel, format: "poules", max_players: 16,
      place: "Padel Club Lyon", status: "open", registered: false,
      date: Date.current + 15, deadline: Date.current + 7,
      description: "Phase de poules puis tableau final. Niveau P100." },

    { name: "Masters Tennis Été", sport: tennis, format: "ronde_suisse", max_players: 16,
      place: "Tennis Club Marseille", status: "in_progress", registered: false,
      date: Date.current + 1, deadline: 3.days.ago,
      description: "Ronde suisse suivie d'un Final 8 en élimination directe." }
  ]

  demo_tournaments.each do |data|
    tournament = Tournament.find_or_create_by!(name: data[:name]) do |t|
      t.sport                 = data[:sport]
      t.format                = data[:format]
      t.max_players           = data[:max_players]
      t.place                 = data[:place]
      t.status                = data[:status]
      t.date                  = data[:date]
      t.time                  = "18:00"
      t.registration_deadline = data[:deadline]
      t.description           = data[:description]
      t.user                  = creator
    end

    # Inscrit le 1er user aux tournois marqués "registered" (→ section "Mes tournois").
    if data[:registered]
      TournamentUser.find_or_create_by!(tournament: tournament, user: creator) do |tu|
        tu.role   = "joueur"
        tu.status = "approved"
      end
    end
  end

  # Ajoute un co-organisateur de démo (2e user, s'il existe) sur un tournoi "open"
  # pour visualiser le rendu du rôle co_organisateur sans passer par le formulaire.
  co_org = User.where.not(id: creator.id).first
  demo_open = Tournament.find_by(name: "Ligue Urbaine Paris")
  if co_org && demo_open
    TournamentUser.find_or_create_by!(tournament: demo_open, user: co_org) do |tu|
      tu.role   = "co_organisateur"
      tu.status = "approved"
    end
  end

  puts "✅ #{Tournament.count} tournois en base."
end
