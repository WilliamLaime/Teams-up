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
