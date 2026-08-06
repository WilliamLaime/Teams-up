# ── Seed de démo : Critérium Fédéral en cours ─────────────────────────────────
# Monte un tournoi de ping-pong au format « Critérium Fédéral », joué jusqu'à
# l'AVANT-DERNIÈRE journée de poules incluse. Il reste donc de vrais résultats à
# saisir, et c'est là que tout le règlement se déclenche en cascade :
#
#   1. terminer les poules → départage FFTT visible dans l'onglet Classement
#      (barème 2 pts par victoire / 1 par défaite, puis quotients de manches et de
#      points restreints au seul sous-groupe d'ex æquo) ;
#   2. les BARRAGES apparaissent : 2es contre 3es, croisés, jamais deux joueurs
#      d'une même poule ;
#   3. tableau final (1ers de poule + vainqueurs de barrage) et CONSOLANTE (4es de
#      poule + perdants de barrage) s'ouvrent en même temps ;
#   4. puis les MATCHS DE CLASSEMENT (3e/4e, 5e-8e…) : chaque place se joue, et
#      l'onglet Classement affiche les places réelles.
#
# Lancement :
#   bin/rails runner db/seeds/criterium_demo.rb
#
# Idempotent : relancer ne recrée rien. Pour repartir de zéro :
#   bin/rails runner 'Tournament.find_by(name: "Critérium Ping Démo")&.destroy'

# Tout le script vit dans un lambda : `return` y est licite (ce n'est pas le cas
# au niveau racine d'un fichier passé à `rails runner`), ce qui permet des gardes
# lisibles plutôt qu'une pyramide de `if`.
demo = lambda do
  tournament_name = "Critérium Ping Démo"
  player_count    = 16

  organizer = User.first
  if organizer.nil?
    puts "⚠️  Aucun utilisateur en base — démo Critérium ignorée."
    return
  end

  sport = Sport.find_by(slug: "ping-pong")
  if sport.nil?
    puts "⚠️  Sport « ping-pong » absent (lancer db/sports.rb) — démo Critérium ignorée."
    return
  end

  if Tournament.exists?(name: tournament_name)
    puts "↳ « #{tournament_name} » existe déjà — rien à faire."
    return
  end

  tournament = Tournament.create!(
    name: tournament_name,
    description: "Démo du format FFTT : poules de 4, barrages, tableau final, consolante " \
                 "et matchs de classement. Les poules sont jouées sauf la dernière journée.",
    sport: sport,
    user: organizer,
    format: "criterium_federal",
    players_per_pool: 4,
    # Variante explicite : à 16 joueurs, les seuils du règlement enverraient ce
    # tournoi en « classement intégral » (un tableau unique, aucun barrage). On
    # veut justement voir les barrages et la consolante → variante standard.
    final_phase_mode: "standard",
    max_players: player_count,
    status: "open",
    date: Date.current + 1,
    place: "Gymnase de démo",
    registration_deadline: 1.day.ago
  )

  # ── Joueurs de démo ─────────────────────────────────────────────────────────
  # De vrais prénoms/noms plutôt que « Pongiste 1..16 » : l'app affiche partout
  # « Prénom N. » (User#short_name), et une liste de « Pongiste 1 vs Pongiste 9 »
  # ne permet pas de vérifier ce rendu. Deux Martin volontaires (Léa et Hugo)
  # pour voir l'initiale faire son travail de désambiguïsation.
  names = [
    %w[Léa Martin],    %w[Hugo Martin],    %w[Camille Bernard], %w[Nathan Dubois],
    %w[Chloé Thomas],  %w[Enzo Robert],    %w[Manon Richard],   %w[Lucas Petit],
    %w[Jade Durand],   %w[Louis Leroy],    %w[Emma Moreau],     %w[Gabriel Simon],
    %w[Alice Laurent], %w[Raphaël Michel], %w[Inès Garcia],     %w[Tom Roux]
  ]

  players = (1..player_count).map do |i|
    first_name, last_name = names[i - 1]
    user = User.find_or_initialize_by(email: "pongiste#{i}@teamup-demo.fr")
    if user.new_record?
      user.assign_attributes(password: "Demo1234!", confirmed_at: Time.current,
                             first_name: first_name, last_name: last_name)
      user.save!
      user.create_profil!(first_name: first_name, last_name: last_name)
    end
    user
  end

  players.each do |player|
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
  end

  # ── Lancement ───────────────────────────────────────────────────────────────
  # Le tirage au sort que fait TournamentsController#start. Ici on le fige dans
  # l'ordre d'inscription : la démo doit être reproductible d'une exécution à
  # l'autre (Pongiste 1 toujours dans la même poule).
  tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
    tu.update_column(:draw_order, index)
  end
  tournament.update!(status: "in_progress")

  # ── Journées de poules, sauf la dernière ────────────────────────────────────
  # 4 joueurs par poule → 3 journées. On en joue 2, la 3e reste à saisir.
  rules  = sport.scoring_rules
  needed = (rules[:best_of] / 2) + 1
  random = Random.new(20_260_806) # scores variés, mais reproductibles

  play_matchday = lambda do
    round = tournament.tournament_rounds.where(phase: "pool").ordered.last
    next if round.nil?

    round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
      # Le vainqueur est TOUJOURS dérivé du score, jamais écrit à la main. On
      # alterne le gagnant selon la position pour que les poules ne se ressemblent pas.
      winner_is_a = match.position.even?
      sets = Array.new(needed) do
        loser_games = random.rand(0..(rules[:target] - 2))
        winner_is_a ? [rules[:target], loser_games] : [loser_games, rules[:target]]
      end
      match.assign_score(sets)
      match.save!
    end
  end

  matchdays_to_play = 2
  matchdays_to_play.times do
    TournamentEngine.for(tournament).next_round!
    play_matchday.call
  end
  # Génère la dernière journée et la laisse VIDE : c'est celle à saisir.
  TournamentEngine.for(tournament).next_round!

  pending = TournamentMatch.joins(:tournament_round)
                           .where(tournament_rounds: { tournament_id: tournament.id })
                           .where(status: "pending", is_bye: false).count

  puts "✅ Tournoi de démo : « #{tournament_name} »"
  puts "   #{player_count} joueurs · #{tournament.pool_count} poules de #{tournament.pool_size} · variante standard"
  puts "   Poules jouées : #{matchdays_to_play}/#{tournament.pool_rounds.count} journées"
  puts "   #{pending} match(s) à saisir pour terminer les poules et déclencher les barrages"
  puts "   Organisateur : #{organizer.email}"
  puts "   Joueurs : pongiste1..#{player_count}@teamup-demo.fr (mot de passe Demo1234!)"
  puts "   → #{Rails.application.routes.url_helpers.tournament_path(tournament)}"
end

demo.call
