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
