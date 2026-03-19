# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ─── ACHIEVEMENTS ─────────────────────────────────────────────────────────────
# On utilise find_or_create_by! pour que ce seed soit idempotent
# (peut être relancé sans créer de doublons)

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
  # ── Catégorie PROFIL ─────────────────────────────────────────────────────────
  {
    key:         "profile_complete",
    name:        "Identité complète",
    description: "Complète ton profil (avatar, description et téléphone)",
    xp_reward:   75,
    icon_emoji:  "👤",
    category:    "profile"
  },
  # ── Nouveaux MATCH ─────────────────────────────────────────────────────────
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
    key:         "organized_10",
    name:        "Général des terrains",
    description: "Organise 10 matchs",
    xp_reward:   400,
    icon_emoji:  "🎖️",
    category:    "match"
  },
  # ── Nouveaux SOCIAL ────────────────────────────────────────────────────────
  {
    key:         "messages_50",
    name:        "Voix du stade",
    description: "Envoie 50 messages au total",
    xp_reward:   250,
    icon_emoji:  "📢",
    category:    "social"
  },
  # ── Nouveaux PROFIL ────────────────────────────────────────────────────────
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

  # ── MATCH — Nouveaux ──────────────────────────────────────────────────────
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

  # ── SOCIAL — Nouveaux ─────────────────────────────────────────────────────
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

  # ── PROFIL — Nouveaux ─────────────────────────────────────────────────────
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
  },
  {
    key:         "comeback",
    name:        "Revenant",
    description: "Reviens jouer après 30 jours d'absence",
    xp_reward:   100,
    icon_emoji:  "🔄",
    category:    "match"
  }
]

achievements_data.each do |data|
  # find_or_create_by! cherche d'abord par la clé unique, crée si introuvable
  achievement = Achievement.find_or_create_by!(key: data[:key]) do |a|
    a.name        = data[:name]
    a.description = data[:description]
    a.xp_reward   = data[:xp_reward]
    a.icon_emoji  = data[:icon_emoji]
    a.category    = data[:category]
  end
  puts "  ✓ #{achievement.icon_emoji} #{achievement.name} (#{achievement.xp_reward} XP)"
end

puts "#{Achievement.count} achievements en base."
# ── Sports de base ────────────────────────────────────────────────────────────
# find_or_create_by! = idempotent (peut être relancé sans créer de doublons)
puts "Création des sports..."

sports_data = [
  { name: "Football",   icon: "⚽", slug: "football"   },
  { name: "Tennis",     icon: "🎾", slug: "tennis"     },
  { name: "Padel",      icon: "sports/padel.png", slug: "padel"      },
  { name: "Volleyball", icon: "🏐", slug: "volleyball" },
  { name: "Basketball", icon: "🏀", slug: "basketball" },
  { name: "Handball",   icon: "🤾", slug: "handball"   },
  { name: "Badminton",  icon: "🏸", slug: "badminton"  }
]

sports_data.each do |sport|
  Sport.find_or_create_by!(slug: sport[:slug]) do |s|
    s.name = sport[:name]
    s.icon = sport[:icon]
  end
end

puts "✅ #{Sport.count} sports créés."

# ── Avis de test ──────────────────────────────────────────────────────────────
# Crée quelques avis fictifs entre les 2 premiers users + leur premier match commun
# Seulement si les conditions sont réunies (users existants, match passé commun)
puts "Création des avis de test..."

# Récupère les 3 premiers users ayant un profil
users_with_profil = User.joins(:profil).limit(3).to_a

if users_with_profil.size >= 2
  # Cherche un match terminé (date dans le passé) avec au moins 2 joueurs approuvés
  completed_match = Match
    .joins(:match_users)
    .where(match_users: { status: "approved" })
    .where("(matches.date + matches.time) < ?", Time.current - 1.hour)
    .group("matches.id")
    .having("COUNT(match_users.id) >= 2")
    .first

  if completed_match
    # Récupère les 2 premiers participants approuvés de ce match
    participants = completed_match.match_users
                                  .where(status: "approved")
                                  .includes(:user)
                                  .limit(2)
                                  .map(&:user)

    if participants.size >= 2
      user_a = participants[0]
      user_b = participants[1]

      # Avis de A vers B
      Avis.find_or_create_by!(
        reviewer:      user_a,
        reviewed_user: user_b,
        match:         completed_match
      ) do |a|
        a.rating  = 5
        a.content = "Super joueur, ponctuel et fair-play. Je recommande !"
      end

      # Avis de B vers A
      Avis.find_or_create_by!(
        reviewer:      user_b,
        reviewed_user: user_a,
        match:         completed_match
      ) do |a|
        a.rating  = 4
        a.content = "Bonne technique, bon esprit d'équipe."
      end

      puts "✅ #{Avis.count} avis de test créés (match : #{completed_match.title})."
    else
      puts "⚠️  Pas assez de participants approuvés dans le match trouvé."
    end
  else
    puts "⚠️  Aucun match terminé trouvé pour créer les avis de test."
  end
else
  puts "⚠️  Pas assez d'utilisateurs avec profil pour créer les avis de test."
end
