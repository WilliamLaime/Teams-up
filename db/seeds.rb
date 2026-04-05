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
    .last

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
        match:         completed_match,
        rating: 5,
        content: "Super joueur, ponctuel et fair-play. Je recommande !")

      # Avis de B vers A
      Avis.find_or_create_by!(
        reviewer:      user_b,
        reviewed_user: user_a,
        match:         completed_match,
        rating: 5,
        content: "Bonne technique, bon esprit d'équipe.")

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

# ── Amis fictifs ──────────────────────────────────────────────────────────────
# Crée 5 utilisateurs avec profil et les lie comme amis acceptés au 1er user
# Idempotent : find_or_create_by! sur l'email
require 'open-uri'
require 'cgi'
puts "Création des amis fictifs..."

# Helper : télécharge un avatar depuis DiceBear et l'attache au profil
# Skippé si l'avatar est déjà présent (idempotent)
# CGI.escape gère les caractères spéciaux dans le seed (accents, etc.)
def attach_seed_avatar(profil, style, seed, filename)
  return if profil.avatar.attached?
  url = "https://api.dicebear.com/7.x/#{style}/png?seed=#{CGI.escape(seed)}&size=200"
  profil.avatar.attach(
    io:           URI.open(url),
    filename:     filename,
    content_type: "image/png"
  )
rescue => e
  puts "  ⚠️  Avatar non chargé (#{filename}) : #{e.message}"
end

# On prend le premier utilisateur en base comme "utilisateur principal"
main_user = User.first

if main_user.nil?
  puts "⚠️  Aucun utilisateur trouvé, les amis fictifs ne seront pas créés."
else
  # avatar_style : "big-ears" pour les hommes, "lorelei" pour les femmes (DiceBear v7)
  fake_friends_data = [
    { first_name: "Lucas",   last_name: "Martin",   email: "lucas.martin@seed.com",   level: "Intermédiaire", localisation: "Paris",     description: "Passionné de foot et de padel, toujours partant pour un match !", avatar_style: "big-ears"  },
    { first_name: "Emma",    last_name: "Dupont",   email: "emma.dupont@seed.com",     level: "Débutant",      localisation: "Lyon",      description: "Nouvelle dans le sport collectif, j'adore le volleyball.",        avatar_style: "lorelei"   },
    { first_name: "Théo",    last_name: "Bernard",  email: "theo.bernard@seed.com",    level: "Expert",        localisation: "Bordeaux",  description: "10 ans de basket, capitaine de mon équipe en amateur.",           avatar_style: "big-ears"  },
    { first_name: "Camille", last_name: "Leroy",    email: "camille.leroy@seed.com",   level: "Intermédiaire", localisation: "Nantes",    description: "Tennis et badminton le week-end, bonne humeur garantie.",         avatar_style: "lorelei"   },
    { first_name: "Noah",    last_name: "Moreau",   email: "noah.moreau@seed.com",     level: "Débutant",      localisation: "Marseille", description: "Je découvre le football à 5, prêt à apprendre !",                 avatar_style: "big-ears"  }
  ]

  fake_friends_data.each do |data|
    # Crée l'utilisateur s'il n'existe pas déjà
    # first_name et last_name sont des attr_accessor requis à la création (pour Devise)
    friend_user = User.find_by(email: data[:email])
    unless friend_user
      friend_user = User.create!(
        email:      data[:email],
        password:   "Password1!",
        first_name: data[:first_name],
        last_name:  data[:last_name]
      )
    end

    # Crée ou met à jour le profil
    profil = friend_user.profil || friend_user.build_profil
    profil.first_name   = data[:first_name]
    profil.last_name    = data[:last_name]
    profil.level        = data[:level]
    profil.localisation = data[:localisation]
    profil.description  = data[:description]
    profil.save!

    # Attache l'avatar DiceBear (skippé si déjà présent)
    attach_seed_avatar(profil, data[:avatar_style], data[:first_name], "#{data[:first_name].downcase}_avatar.png")

    # Crée l'amitié acceptée si elle n'existe pas encore
    already_friends = Friendship.exists?(user: main_user, friend: friend_user) ||
                      Friendship.exists?(user: friend_user, friend: main_user)

    unless already_friends
      Friendship.create!(
        user:   main_user,
        friend: friend_user,
        status: "accepted"
      )
      puts "  ✓ Ami créé : #{data[:first_name]} #{data[:last_name]}"
    else
      puts "  → Déjà ami : #{data[:first_name]} #{data[:last_name]}"
    end
  end

  puts "✅ #{main_user.all_friends.count} amis au total pour #{main_user.email}."
end

# ── Joueurs invitables (sans amitié, juste des comptes existants) ──────────────
# Ces joueurs peuvent être invités via la recherche par email ou prénom
puts "Création des joueurs invitables..."

invitable_data = [
  { first_name: "Jules",  last_name: "Petit",    email: "jules.petit@seed.com",    level: "Intermédiaire", localisation: "Toulouse",    description: "Footeux du dimanche, mais sérieux quand il le faut.",         avatar_style: "big-ears" },
  { first_name: "Inès",   last_name: "Rousseau", email: "ines.rousseau@seed.com",  level: "Expert",        localisation: "Strasbourg",  description: "Capitaine de mon équipe de handball en D3 régionale.",        avatar_style: "lorelei"  }
]

invitable_data.each do |data|
  # Crée le compte s'il n'existe pas encore
  user = User.find_by(email: data[:email])
  unless user
    user = User.create!(
      email:      data[:email],
      password:   "Password1!",
      first_name: data[:first_name],
      last_name:  data[:last_name]
    )
  end

  # Crée ou met à jour le profil
  profil = user.profil || user.build_profil
  profil.first_name   = data[:first_name]
  profil.last_name    = data[:last_name]
  profil.level        = data[:level]
  profil.localisation = data[:localisation]
  profil.description  = data[:description]
  profil.save!

  # Attache l'avatar DiceBear (skippé si déjà présent)
  avatar_url = "https://api.dicebear.com/7.x/#{data[:avatar_style]}/png?seed=#{data[:first_name]}&size=200"
  attach_seed_avatar(profil, avatar_url, "#{data[:first_name].downcase}_avatar.png")

  # Lie comme ami accepté avec le main_user (pour apparaître dans "Proposer un joueur")
  if main_user
    already_friends = Friendship.exists?(user: main_user, friend: user) ||
                      Friendship.exists?(user: user, friend: main_user)
    unless already_friends
      Friendship.create!(user: main_user, friend: user, status: "accepted")
    end
  end

  puts "  ✓ Joueur invitable : #{data[:first_name]} #{data[:last_name]} (#{data[:email]})"
end

puts "✅ Joueurs invitables créés."
