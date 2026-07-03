# ─────────────────────────────────────────────────────────────────────────────
# Rake task : crée 50 matchs réalistes en base (production ou local)
#
# Usage :
#   rails matches:seed_50
#
# Idempotente : chaque match est retrouvé ou créé par son titre exact.
# Les organisateurs sont tirés au hasard parmi tous les comptes inscrits.
# ─────────────────────────────────────────────────────────────────────────────

namespace :matches do
  desc "Crée 50 matchs réalistes répartis sur les 7 sports"
  task seed_50: :environment do
    # ── Récupère les sports ──────────────────────────────────────────────────
    football   = Sport.find_by(slug: "football")
    tennis     = Sport.find_by(slug: "tennis")
    padel      = Sport.find_by(slug: "padel")
    volleyball = Sport.find_by(slug: "volleyball")
    basketball = Sport.find_by(slug: "basketball")
    handball   = Sport.find_by(slug: "handball")
    badminton  = Sport.find_by(slug: "badminton")

    missing = [football, tennis, padel, volleyball, basketball, handball, badminton].count(&:nil?)
    if missing > 0
      puts "❌ #{missing} sport(s) introuvable(s) — lance d'abord rails db:seed"
      exit 1
    end

    # ── Récupère les utilisateurs existants ──────────────────────────────────
    users = User.all.to_a
    if users.empty?
      puts "❌ Aucun utilisateur en base — inscris-toi d'abord sur le site"
      exit 1
    end

    puts "👥 #{users.count} compte(s) disponible(s) comme organisateur"

    # ── Données des 50 matchs ────────────────────────────────────────────────
    # Chaque hash : title, sport, level, format, player_left, place, date,
    #               time (string HH:MM), description, validation_mode,
    #               price_per_player, visibility, genre_restriction
    # date = entier : nombre de jours à partir d'aujourd'hui
    # ─────────────────────────────────────────────────────────────────────────
    matches_data = [

      # ══ FOOTBALL (8 matchs) ══════════════════════════════════════════════

      {
        title:           "Football 5v5 — Paris 15e, ambiance garantie",
        sport:           football,
        level:           "Amateur",
        format:          "5v5",
        player_left:     4,
        place:           "Stade Émile Anthoine, Paris 15",
        date_offset:     1,
        time:            "18:30",
        description:     "Match 5v5 dans un cadre sympa. Tous niveaux amateurs bienvenus, l'essentiel c'est de se dépenser !",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "11v11 dominical — Stade Charléty",
        sport:           football,
        level:           "Intermédiaire",
        format:          "11v11",
        player_left:     14,
        place:           "Stade Charléty, Paris 13",
        date_offset:     3,
        time:            "10:00",
        description:     "Grand format 11v11 le dimanche matin. Terrain synthétique, crampons vissés interdits.",
        validation_mode: "manual",
        price_per_player: 5,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 soir en semaine — Lyon Part-Dieu",
        sport:           football,
        level:           "Débutant",
        format:          "5v5",
        player_left:     3,
        place:           "Gymnase Tony Burnand, Lyon 3",
        date_offset:     2,
        time:            "19:30",
        description:     "Petite partie détente après le boulot. Débutants et repreneurs les bienvenus.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Match libre — Plaine de Jeux Bagatelle",
        sport:           football,
        level:           "Amateur",
        format:          "Libre",
        player_left:     6,
        place:           "Plaine de Jeux de Bagatelle, Paris 16",
        date_offset:     5,
        time:            "15:00",
        description:     "Format libre, on s'adapte au nombre de joueurs présents. Aire de jeu en plein air.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 confirmé — Complexe Sportif Diderot",
        sport:           football,
        level:           "Confirmé",
        format:          "5v5",
        player_left:     2,
        place:           "Complexe Sportif Diderot, Paris 12",
        date_offset:     7,
        time:            "20:00",
        description:     "Niveau confirmé, pressing et transition rapide attendus. Pas de place pour les noctambules sans ballon.",
        validation_mode: "manual",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 Bordeaux — Terrain synthétique Bacalan",
        sport:           football,
        level:           "Amateur",
        format:          "5v5",
        player_left:     5,
        place:           "Terrain Synthétique Bacalan, Bordeaux",
        date_offset:     4,
        time:            "18:00",
        description:     "Match de quartier convivial. On joue, on rigole, on remet ça la semaine prochaine.",
        validation_mode: "automatic",
        price_per_player: 2,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "11v11 Marseille — Stade de la Capelette",
        sport:           football,
        level:           "Intermédiaire",
        format:          "11v11",
        player_left:     10,
        place:           "Stade de la Capelette, Marseille",
        date_offset:     10,
        time:            "09:00",
        description:     "Grand format 11v11 le week-end à Marseille. Terrain en herbe naturelle, gardiens recherchés.",
        validation_mode: "automatic",
        price_per_player: 4,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 Expert — Paris FC Academy Turf",
        sport:           football,
        level:           "Expert",
        format:          "5v5",
        player_left:     3,
        place:           "Paris FC Academy, Paris 13",
        date_offset:     6,
        time:            "21:00",
        description:     "Intensité max, touches comptées, pressing constant. Réservé aux joueurs d'un bon niveau.",
        validation_mode: "manual",
        price_per_player: 6,
        visibility:      "public",
        genre_restriction: "tous"
      },

      # ══ PADEL (8 matchs) ═════════════════════════════════════════════════

      {
        title:           "Padel 2v2 — Intermédiaire, Paris 11",
        sport:           padel,
        level:           "Intermédiaire",
        format:          "2v2",
        player_left:     3,
        place:           "Padel Club Paris 11, Paris",
        date_offset:     1,
        time:            "14:00",
        description:     "Match de padel amical 2v2. Niveau intermédiaire, bonne maîtrise des échanges attendue.",
        validation_mode: "automatic",
        price_per_player: 10,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel débutant — Urban Padel Paris 12",
        sport:           padel,
        level:           "Débutant",
        format:          "2v2",
        player_left:     2,
        place:           "Urban Padel, Paris 12",
        date_offset:     2,
        time:            "11:00",
        description:     "Initiation padel pour débutants. On explique les règles, on prend le temps de jouer.",
        validation_mode: "manual",
        price_per_player: 8,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel confirmé — Toulouse Padel Club",
        sport:           padel,
        level:           "Confirmé",
        format:          "2v2",
        player_left:     1,
        place:           "Toulouse Padel Club, Toulouse",
        date_offset:     3,
        time:            "10:30",
        description:     "Niveau confirmé, jeu au filet maîtrisé. Match sérieux en perspective.",
        validation_mode: "automatic",
        price_per_player: 12,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel libre — 4 joueurs bienvenus",
        sport:           padel,
        level:           "Amateur",
        format:          "Libre",
        player_left:     3,
        place:           "Padel Horizon, Lyon",
        date_offset:     4,
        time:            "16:00",
        description:     "Format libre pour jouer entre amis ou rencontrer de nouveaux partenaires.",
        validation_mode: "automatic",
        price_per_player: 7,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel 2v2 — Nantes, niveau Perfectionnement",
        sport:           padel,
        level:           "Perfectionnement",
        format:          "2v2",
        player_left:     3,
        place:           "Padel Nantes Atlantique, Nantes",
        date_offset:     5,
        time:            "09:00",
        description:     "Pour les joueurs qui progressent : échanges réguliers, premiers tournois. Bonne ambiance.",
        validation_mode: "manual",
        price_per_player: 9,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel Avancé — Bordeaux Padel Indoor",
        sport:           padel,
        level:           "Avancé",
        format:          "2v2",
        player_left:     2,
        place:           "Bordeaux Padel Indoor, Bordeaux",
        date_offset:     8,
        time:            "19:00",
        description:     "Haut niveau amateur, jeu rapide et précis. Cherche deux partenaires sérieux.",
        validation_mode: "manual",
        price_per_player: 14,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Ladies Padel — Paris, 2v2 mixte ouvert",
        sport:           padel,
        level:           "Intermédiaire",
        format:          "2v2",
        player_left:     3,
        place:           "Padel Club Boulogne, Boulogne-Billancourt",
        date_offset:     9,
        time:            "13:00",
        description:     "Ouvert à toutes et tous, atmosphère décontractée. On se retrouve pour un bon match.",
        validation_mode: "automatic",
        price_per_player: 10,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Padel Expert — Lille Grand Palais",
        sport:           padel,
        level:           "Expert",
        format:          "2v2",
        player_left:     1,
        place:           "Padel Club Lille, Lille",
        date_offset:     12,
        time:            "18:30",
        description:     "Niveau Expert P2000+. Match intense, cherche un 4e partenaire de très bon niveau.",
        validation_mode: "manual",
        price_per_player: 16,
        visibility:      "public",
        genre_restriction: "tous"
      },

      # ══ TENNIS (7 matchs) ════════════════════════════════════════════════

      {
        title:           "Tennis simple — Confirmé, Paris 17",
        sport:           tennis,
        level:           "Confirmé",
        format:          "1v1",
        player_left:     1,
        place:           "Tennis Club de la Faïencerie, Paris 17",
        date_offset:     2,
        time:            "09:00",
        description:     "Simple masculin ou féminin, niveau confirmé. Court en dur intérieur.",
        validation_mode: "automatic",
        price_per_player: 8,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis double — Élémentaire, Jardin du Luxembourg",
        sport:           tennis,
        level:           "Élémentaire",
        format:          "2v2",
        player_left:     3,
        place:           "Courts du Jardin du Luxembourg, Paris 6",
        date_offset:     5,
        time:            "16:00",
        description:     "Double mixte sur court en dur. Balle jaune, premiers matchs en compétition.",
        validation_mode: "manual",
        price_per_player: 6,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis simple — Intermédiaire, Lyon",
        sport:           tennis,
        level:           "Intermédiaire",
        format:          "1v1",
        player_left:     1,
        place:           "Tennis Club de Lyon, Lyon",
        date_offset:     3,
        time:            "11:00",
        description:     "Simple niveau intermédiaire (série 30). Jeu varié attendu, fond de court ou montées.",
        validation_mode: "automatic",
        price_per_player: 5,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis simple Avancé — Stade Roland-Garros abords",
        sport:           tennis,
        level:           "Avancé",
        format:          "1v1",
        player_left:     1,
        place:           "Tennis Club Stade Français, Paris 16",
        date_offset:     7,
        time:            "08:30",
        description:     "Simple niveau avancé, maîtrise des zones et trajectoires. Court en terre battue.",
        validation_mode: "manual",
        price_per_player: 10,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis double — Confirmé, Marseille",
        sport:           tennis,
        level:           "Confirmé",
        format:          "2v2",
        player_left:     2,
        place:           "Tennis Club de Marseille, Marseille",
        date_offset:     11,
        time:            "10:00",
        description:     "Double messieurs ou mixte, niveau confirmé. Bon jeu au filet apprécié.",
        validation_mode: "automatic",
        price_per_player: 8,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis libre — Bordeaux, plusieurs créneaux",
        sport:           tennis,
        level:           "Amateur",
        format:          "Libre",
        player_left:     3,
        place:           "Tennis Club Bordeaux-Caudéran, Bordeaux",
        date_offset:     6,
        time:            "14:30",
        description:     "Format libre pour s'entraîner ou disputer un match. On s'adapte au nombre.",
        validation_mode: "automatic",
        price_per_player: 4,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Tennis simple débutant — Strasbourg",
        sport:           tennis,
        level:           "Débutant",
        format:          "1v1",
        player_left:     1,
        place:           "Tennis Club de Strasbourg, Strasbourg",
        date_offset:     14,
        time:            "17:00",
        description:     "Découverte du tennis en simple. Balles vertes disponibles sur place, encadrement bienveillant.",
        validation_mode: "automatic",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      },

      # ══ BASKETBALL (7 matchs) ════════════════════════════════════════════

      {
        title:           "Basketball 3v3 — Confirmé, Paris 19",
        sport:           basketball,
        level:           "Confirmé",
        format:          "3v3",
        player_left:     2,
        place:           "Gymnase Jean-Jaurès, Paris 19",
        date_offset:     1,
        time:            "19:00",
        description:     "3v3 intense, niveau confirmé uniquement. Physique et shoot au programme.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Basketball 5v5 — Amateur, Paris 5",
        sport:           basketball,
        level:           "Amateur",
        format:          "5v5",
        player_left:     5,
        place:           "Gymnase Lakanal, Paris 5",
        date_offset:     4,
        time:            "20:30",
        description:     "5v5 décontracté, ambiance bonne humeur garantie. Tous niveaux amateurs.",
        validation_mode: "manual",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Streetball 3v3 — Paris, terrains Coubertin",
        sport:           basketball,
        level:           "Intermédiaire",
        format:          "3v3",
        player_left:     4,
        place:           "Stade Pierre de Coubertin, Paris 16",
        date_offset:     3,
        time:            "17:00",
        description:     "Streetball en plein air, format 3v3 en demi-terrain. Pas de renvoi en zone.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 Expert — Lyon Villeurbanne",
        sport:           basketball,
        level:           "Expert",
        format:          "5v5",
        player_left:     3,
        place:           "Gymnase Tony Parker, Villeurbanne",
        date_offset:     8,
        time:            "20:00",
        description:     "Niveau expert, jeu rapide avec systèmes offensifs. Cherche trois joueurs solides.",
        validation_mode: "manual",
        price_per_player: 5,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Basketball 2v2 — Débutant, Paris 20",
        sport:           basketball,
        level:           "Débutant",
        format:          "2v2",
        player_left:     2,
        place:           "Gymnase Municipal Télégraphe, Paris 20",
        date_offset:     6,
        time:            "10:00",
        description:     "Initiation basket en format réduit. Travail de dribble, passe et tir. Débutants only.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "5v5 — Nantes, salle couverte",
        sport:           basketball,
        level:           "Intermédiaire",
        format:          "5v5",
        player_left:     6,
        place:           "Gymnase de la Beaujoire, Nantes",
        date_offset:     9,
        time:            "19:30",
        description:     "5v5 pleine salle à Nantes. Niveau intermédiaire, jeu collectif apprécié.",
        validation_mode: "automatic",
        price_per_player: 2,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "1v1 Challenge — Qui est le meilleur ?",
        sport:           basketball,
        level:           "Confirmé",
        format:          "1v1",
        player_left:     1,
        place:           "Terrain extérieur Oberkampf, Paris 11",
        date_offset:     13,
        time:            "18:00",
        description:     "Défi 1v1 en plein air. Jusqu'à 11 points, alterné, prime au premier servi.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },

      # ══ VOLLEYBALL (7 matchs) ════════════════════════════════════════════

      {
        title:           "Volleyball 6v6 — Intermédiaire, Paris 15",
        sport:           volleyball,
        level:           "Intermédiaire",
        format:          "6v6",
        player_left:     5,
        place:           "Gymnase Élisabeth, Paris 15",
        date_offset:     1,
        time:            "20:00",
        description:     "6v6 classique, service flottant toléré. Rotation obligatoire, arbitrage tournant.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Beach Volley 3v3 — Villette, Paris",
        sport:           volleyball,
        level:           "Débutant",
        format:          "3v3",
        player_left:     5,
        place:           "Beach de la Villette, Paris 19",
        date_offset:     3,
        time:            "14:00",
        description:     "Beach volley décontracté en plein air. Parfait pour les débutants et les repreneurs.",
        validation_mode: "manual",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "6v6 Confirmé — Gymnase Toulouse Métropole",
        sport:           volleyball,
        level:           "Confirmé",
        format:          "6v6",
        player_left:     4,
        place:           "Gymnase des Argoulets, Toulouse",
        date_offset:     5,
        time:            "19:00",
        description:     "Volley confirmé avec rotation et système de jeu défini. Match arbitré.",
        validation_mode: "manual",
        price_per_player: 2,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Volley libre — format adapté au groupe",
        sport:           volleyball,
        level:           "Amateur",
        format:          "Libre",
        player_left:     4,
        place:           "Gymnase Léo Lagrange, Lyon",
        date_offset:     7,
        time:            "18:30",
        description:     "On joue à combien on est. Format et règles adaptés à la session, venez nombreux.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "6v6 Amateur — Lille, gymnase couvert",
        sport:           volleyball,
        level:           "Amateur",
        format:          "6v6",
        player_left:     8,
        place:           "Gymnase Léon Trulin, Lille",
        date_offset:     10,
        time:            "20:30",
        description:     "Match de volley amateur complet. Terrains couverts, filet réglementaire.",
        validation_mode: "automatic",
        price_per_player: 1,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "3v3 Expert — Paris, qui s'y frotte s'y pique",
        sport:           volleyball,
        level:           "Expert",
        format:          "3v3",
        player_left:     3,
        place:           "Stade Charlety, Paris 13",
        date_offset:     15,
        time:            "19:00",
        description:     "Format réduit ultra-intense. Niveau expert, smash et contre attendus.",
        validation_mode: "manual",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Volley Féminin 6v6 — Paris, accès libre",
        sport:           volleyball,
        level:           "Intermédiaire",
        format:          "6v6",
        player_left:     6,
        place:           "Gymnase Pierre Curie, Paris 5",
        date_offset:     18,
        time:            "17:30",
        description:     "Session réservée aux femmes, esprit collectif et progressif. Venez jouer !",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "feminin"
      },

      # ══ HANDBALL (7 matchs) ══════════════════════════════════════════════

      {
        title:           "Handball 6v6 — Amateur, Paris 13",
        sport:           handball,
        level:           "Amateur",
        format:          "6v6",
        player_left:     6,
        place:           "Gymnase Berthelot, Paris 13",
        date_offset:     2,
        time:            "19:30",
        description:     "Handball 6v6 amical. Rejoins directement, validation automatique.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Handball libre — Paris, format adapté",
        sport:           handball,
        level:           "Intermédiaire",
        format:          "Libre",
        player_left:     4,
        place:           "Gymnase Paul Valéry, Paris 12",
        date_offset:     6,
        time:            "21:00",
        description:     "Format libre adapté au nombre de joueurs. Niveau intermédiaire.",
        validation_mode: "manual",
        price_per_player: 4,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "6v6 Confirmé — Nantes, gymnase couvert",
        sport:           handball,
        level:           "Confirmé",
        format:          "6v6",
        player_left:     5,
        place:           "Gymnase de la Prairie de Mauves, Nantes",
        date_offset:     4,
        time:            "20:00",
        description:     "Handball confirmé, jeu structuré avec systèmes défensifs 6-0 ou 5-1.",
        validation_mode: "manual",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Handball Expert — Strasbourg",
        sport:           handball,
        level:           "Expert",
        format:          "6v6",
        player_left:     2,
        place:           "Halle Rhénane, Strasbourg",
        date_offset:     8,
        time:            "18:00",
        description:     "Match de haut niveau amateur. Vitesse d'exécution et précision au tir attendues.",
        validation_mode: "manual",
        price_per_player: 5,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "6v6 Débutant — Bordeaux, initiation collective",
        sport:           handball,
        level:           "Débutant",
        format:          "6v6",
        player_left:     8,
        place:           "Gymnase Robert Cousin, Bordeaux",
        date_offset:     11,
        time:            "10:00",
        description:     "Initiation handball 6v6. Règles expliquées sur place, bonne humeur obligatoire.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Handball Intermédiaire — Marseille",
        sport:           handball,
        level:           "Intermédiaire",
        format:          "6v6",
        player_left:     7,
        place:           "Gymnase Vallon de Rouet, Marseille",
        date_offset:     16,
        time:            "19:00",
        description:     "Handball 6v6 intermédiaire à Marseille. Cherche des joueurs réguliers.",
        validation_mode: "automatic",
        price_per_player: 2,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "6v6 Amateur Mixte — Toulouse, salle climatisée",
        sport:           handball,
        level:           "Amateur",
        format:          "6v6",
        player_left:     9,
        place:           "Gymnase Municipal Toulouse-Lardenne, Toulouse",
        date_offset:     20,
        time:            "20:30",
        description:     "Match mixte décontracté. Bonne atmosphère, pas de prise de tête.",
        validation_mode: "automatic",
        price_per_player: 1,
        visibility:      "public",
        genre_restriction: "tous"
      },

      # ══ BADMINTON (6 matchs) ═════════════════════════════════════════════

      {
        title:           "Badminton simple — Initié, Paris 14",
        sport:           badminton,
        level:           "Initié",
        format:          "1v1",
        player_left:     1,
        place:           "Gymnase Rodin, Paris 14",
        date_offset:     1,
        time:            "20:00",
        description:     "Simple badminton niveau initié. Échanges réguliers, premiers matchs en compétition.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Badminton double — Confirmé, Paris 11",
        sport:           badminton,
        level:           "Confirmé",
        format:          "2v2",
        player_left:     3,
        place:           "Badminton Club de Paris 11",
        date_offset:     4,
        time:            "18:00",
        description:     "Double badminton niveau confirmé. Jeu rapide, placement tactique maîtrisé.",
        validation_mode: "manual",
        price_per_player: 5,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Badminton simple Expert — Lyon",
        sport:           badminton,
        level:           "Expert",
        format:          "1v1",
        player_left:     1,
        place:           "Gymnase des Charpennes, Villeurbanne",
        date_offset:     7,
        time:            "19:30",
        description:     "Niveau Expert, jeu à haute vitesse et intensité. Série A ou équivalent.",
        validation_mode: "manual",
        price_per_player: 4,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Badminton libre — Paris, tous niveaux",
        sport:           badminton,
        level:           "Intermédiaire",
        format:          "Libre",
        player_left:     4,
        place:           "Gymnase Charles Hermite, Paris 18",
        date_offset:     5,
        time:            "12:30",
        description:     "Session badminton libre. Format adapté au niveau et au nombre de participants.",
        validation_mode: "automatic",
        price_per_player: 2,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Badminton simple — Débutant, Nantes",
        sport:           badminton,
        level:           "Débutant",
        format:          "1v1",
        player_left:     1,
        place:           "Gymnase Alphonse Orsat, Nantes",
        date_offset:     12,
        time:            "14:00",
        description:     "Initiation badminton en simple. Découverte des coups de base, volants fournis.",
        validation_mode: "automatic",
        price_per_player: 0,
        visibility:      "public",
        genre_restriction: "tous"
      },
      {
        title:           "Badminton double — Intermédiaire, Lille",
        sport:           badminton,
        level:           "Intermédiaire",
        format:          "2v2",
        player_left:     2,
        place:           "Gymnase du Faubourg de Béthune, Lille",
        date_offset:     19,
        time:            "20:00",
        description:     "Double badminton, niveau série C. Match complet avec pointage réglementaire.",
        validation_mode: "automatic",
        price_per_player: 3,
        visibility:      "public",
        genre_restriction: "tous"
      }

    ]

    # ── Création des matchs ──────────────────────────────────────────────────
    puts "🚀 Création de #{matches_data.size} matchs..."
    created_count  = 0
    skipped_count  = 0

    matches_data.each do |data|
      # Idempotence : on ne recrée pas un match qui existe déjà
      if Match.exists?(title: data[:title])
        puts "  → Déjà existant : #{data[:title]}"
        skipped_count += 1
        next
      end

      # Calcul de la date et de l'heure complètes
      match_date = Date.today + data[:date_offset]
      h, m       = data[:time].split(":").map(&:to_i)
      match_time = Time.zone.local(match_date.year, match_date.month, match_date.day, h, m, 0)

      # Décale d'une heure si la datetime est trop proche (moins de 30 min dans le futur)
      if match_time < Time.current + 30.minutes
        match_time += 1.hour
        match_date  = match_time.to_date
        h           = match_time.hour
        m           = match_time.min
      end

      # Choisit un organisateur au hasard parmi tous les comptes
      organizer = users.sample

      match = Match.new(
        title:            data[:title],
        sport:            data[:sport],
        level:            data[:level],
        format:           data[:format],
        players_needed:   data[:player_left], # capacité cible ; player_left est recalculé par callback
        place:            data[:place],
        date:             match_date,
        time:             Time.zone.local(match_date.year, match_date.month, match_date.day, h, m, 0),
        description:      data[:description],
        validation_mode:  data[:validation_mode],
        price_per_player: data[:price_per_player],
        visibility:       data[:visibility],
        genre_restriction: data[:genre_restriction],
        user:             organizer
      )

      if match.save
        # Inscrit l'organisateur en tant que tel (normalement géré par le controller)
        MatchUser.find_or_create_by!(match: match, user: organizer) do |mu|
          mu.role   = "organisateur"
          mu.status = "approved"
        end
        puts "  ✓ [#{data[:sport].name}] #{data[:title]} — orga: #{organizer.email}"
        created_count += 1
      else
        puts "  ✗ Échec '#{data[:title]}' : #{match.errors.full_messages.join(', ')}"
      end
    end

    puts ""
    puts "✅ Terminé ! #{created_count} matchs créés, #{skipped_count} ignorés (déjà existants)."
    puts "   Total matchs en base : #{Match.count}"
  end
end
