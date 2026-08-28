# ── Seed : « Tournoi test chapeaux — CACD2 » (Critérium, 25 joueurs) ──────────
# Troisième variante de recette, après tournoi_test_cacd2_lcl.rb (32 joueurs, 8
# poules de 4 — le cas parfaitement pair) et tournoi_test_impair.rb (17 joueurs,
# une poule de 2). Celle-ci vise un mécanisme que les deux autres n'exercent PAS :
# la constitution des poules par CHAPEAUX (`Tournament::POOL_SEEDING_MODES`, Lot 7).
#
# Les deux seeds existantes laissent `pool_seeding_mode` à nil, donc en mode
# "random" (serpentin sur le tirage). `PoolSeeding#assign_by_pots!` n'a par
# conséquent jamais tourné sur un vrai tournoi.
#
# ── Ce que ce tournoi sert à mettre à l'épreuve ───────────────────────────────
#   • L'écran Constitution : passer en mode chapeaux, choisir leur nombre, et
#     répartir 25 joueurs à la main dans les chapeaux 1, 2 et le chapeau général.
#   • `PoolSeeding#seat_pots!` : chaque chapeau numéroté doit fournir UN joueur
#     par poule, et le chapeau général compléter les poules les moins remplies.
#   • Trois POULES IMPAIRES (le plan est [4, 4, 4, 4, 3, 3, 3]) : leur round-robin
#     se joue avec un bye tournant, qui ne doit rapporter ni victoire ni match
#     joué au classement (cf. PoolStandings et RoundRobinStats#recompute_stats_for
#     avec `count_byes: false`). Le départage se fait alors sur la confrontation
#     directe puis les quotients de manches et de points, exactement comme dans
#     une poule paire.
#   • Un tableau final de 7 poules × 2 = 14 entrants, donc PAS une puissance de
#     deux : tableau de 16 avec 2 byes.
#   • Le DOUBLE RÔLE : les trois organisateurs jouent le tournoi qu'ils gèrent.
#     C'est nouveau — jusqu'ici un co-organisateur ne pouvait pas occuper de place
#     (cf. la colonne `tournament_users.co_organizer`, qui sépare enfin « occupe
#     une place » de « a les droits de gestion »).
#
# État obtenu : tournoi PRÊT À ÊTRE LANCÉ, mais PAS lancé, et surtout avec les
# CHAPEAUX VIDES. Les 25 inscriptions sont posées, le mode chapeaux est armé, mais
# aucun joueur n'a de numéro : tout le monde part au chapeau général. C'est
# l'organisateur qui les répartit depuis l'onglet Constitution, PUIS qui clique
# « Lancer le tournoi ». Le pré-remplir ici viderait la recette de son objet.
#
# ── Lancement ────────────────────────────────────────────────────────────────
#   bin/rails runner db/seeds/tournoi_test_chapeaux.rb
#
# En production sur Railway, DANS le conteneur du service web :
#   railway ssh --service Teams-up bin/rails runner db/seeds/tournoi_test_chapeaux.rb
#
# ⚠️ Et NON `railway run` : celui-ci exécute la commande sur la machine locale en y
# injectant les variables du service. Or `DATABASE_URL` pointe sur un hôte
# `*.railway.internal`, qui n'est joignable que depuis le réseau Railway — la
# connexion échoue donc depuis un poste de dev. `railway ssh` exécute bel et bien
# dans le conteneur, où cet hôte résout. Corollaire : le fichier doit être DÉPLOYÉ
# (il vient de l'image, pas du poste local).
#
# Idempotent : relancer ne recrée rien. Pour repartir de zéro :
#   RESET=1 bin/rails runner db/seeds/tournoi_test_chapeaux.rb
#
# ── Variables d'environnement ────────────────────────────────────────────────
#   ADMIN_EMAIL      email de l'administrateur du tournoi (défaut : recherche
#                    « Antoine Lozach » par son profil)
#   CO_ORG_EMAILS    emails des co-organisateurs, séparés par des virgules
#                    (défaut : « Olivier Parinet » et « William Laimé »)
#   PLAYER_PASSWORD  mot de passe commun aux 22 comptes de test. Par défaut CHACUN
#                    reçoit un mot de passe aléatoire : ces comptes vivent en
#                    production, un mot de passe connu et deviné depuis le motif des
#                    emails permettrait de s'y connecter et de publier dans l'app sous
#                    une fausse identité. À ne renseigner que pour tester
#                    délibérément la vue « joueur ».
#   RESET=1          supprime le tournoi existant avant de le recréer
#
# Pas de START= ici, contrairement à tournoi_test_impair.rb : lancer le tournoi
# appellerait PoolSeeding avant que les chapeaux soient remplis, donc en réduirait
# la répartition à celle du chapeau général. Ce serait l'inverse du but.
#
# ── Purge des comptes de test ────────────────────────────────────────────────
# Ne touche QUE les 22 comptes fictifs : les trois organisateurs sont de vrais
# comptes, ils jouent mais ne doivent évidemment pas être supprimés avec la recette.
#   User.where("email LIKE 'chapeau%@teamup-demo.fr'").destroy_all

# Tout le script vit dans un lambda : `return` y est licite (ce n'est pas le cas
# au niveau racine d'un fichier passé à `rails runner`), ce qui permet des gardes
# lisibles plutôt qu'une pyramide de `if`.
seed = lambda do
  tournament_name = "Tournoi test chapeaux — CACD2"
  player_count    = 25
  players_in_pool = 4  # 25 / 4 → 7 poules, réparties en [4, 4, 4, 4, 3, 3, 3]
  pot_count       = 2  # 7 poules → chapeau 1 = 7 joueurs, chapeau 2 = 7, général = 11
  email_domain    = "teamup-demo.fr"
  email_prefix    = "chapeau"

  # ── Résolution des organisateurs ────────────────────────────────────────────
  # Recherche par PROFIL et non par User : `User#first_name` / `#last_name` sont
  # de simples attr_accessor (utilisés à la création), les vrais noms vivent dans
  # `profils`. En production, préférer les ENV : un homonyme ou un accent différent
  # suffirait à faire échouer la recherche par nom.
  find_by_name = lambda do |first, last|
    Profil.where("first_name ILIKE ? AND last_name ILIKE ?", first, last).first&.user
  end

  find_by_email = lambda do |email|
    User.find_by(email: email).tap do |user|
      puts "⚠️  Aucun compte pour #{email} — ignoré." if user.nil?
    end
  end

  co_org_emails = ENV.fetch("CO_ORG_EMAILS", "").split(",").map(&:strip).reject(&:empty?)

  admin = if ENV["ADMIN_EMAIL"].present?
            find_by_email.call(ENV["ADMIN_EMAIL"])
          else
            find_by_name.call("Antoine", "Lozach")
          end

  co_organizers =
    if co_org_emails.any?
      co_org_emails.filter_map { |email| find_by_email.call(email) }
    else
      [["Olivier", "Parinet"], ["William", "Laimé"]].filter_map do |first, last|
        person = find_by_name.call(first, last)
        puts "⚠️  « #{first} #{last} » introuvable — à ajouter à la main comme co-organisateur." if person.nil?
        person
      end
    end

  # Sans administrateur, pas de tournoi : `tournament.user` est obligatoire et
  # c'est lui qui porte les droits de gestion.
  if admin.nil?
    admin = co_organizers.first
    if admin.nil?
      puts "❌ Ni « Antoine Lozach » ni aucun co-organisateur trouvé en base."
      puts "   Relancer avec ADMIN_EMAIL=... (et CO_ORG_EMAILS=...) une fois les comptes créés."
      return
    end
    puts "⚠️  « Antoine Lozach » introuvable : #{admin.email} devient administrateur du tournoi."
    puts "   → À réaffecter depuis l'app une fois son compte créé."
    co_organizers -= [admin] # jamais co-organisateur de son propre tournoi
  end

  co_organizers = co_organizers.uniq - [admin]
  # Les organisateurs occupent des places de joueur : il reste ce qu'ils laissent.
  fake_count = player_count - 1 - co_organizers.size

  sport = Sport.find_by(slug: "ping-pong")
  if sport.nil?
    puts "❌ Sport « ping-pong » absent (lancer `rails db:seed_sports`)."
    return
  end

  existing = Tournament.find_by(name: tournament_name)
  if existing
    if ENV["RESET"] == "1"
      puts "♻️  Suppression du tournoi existant « #{tournament_name} » (##{existing.id})…"
      existing.destroy!
    else
      puts "↳ « #{tournament_name} » existe déjà : /tournois/#{existing.slug}"
      puts "   RESET=1 pour le recréer de zéro."
      return
    end
  end

  # ── Le tournoi ──────────────────────────────────────────────────────────────
  tournament = Tournament.create!(
    name: tournament_name,
    description: "Tournoi de recette de la constitution par CHAPEAUX : 25 joueurs en " \
                 "poules de 4, soit 4 poules de 4 et 3 poules de 3. Les chapeaux sont " \
                 "armés mais VIDES — à l'organisateur de répartir les joueurs depuis " \
                 "l'onglet Constitution avant de lancer le tournoi. " \
                 "Les résultats sont à saisir librement : rien n'est joué au départ.",
    sport: sport,
    user: admin,
    format: "criterium_federal",
    players_per_pool: players_in_pool,
    # Explicite : à 25 joueurs les seuils du règlement donneraient déjà "standard",
    # mais on ne veut pas qu'un ajustement de ces seuils change la recette (on tient
    # aux barrages et à la consolante).
    final_phase_mode: "standard",
    # 25 n'est pas un preset (PLAYER_COUNTS = [8, 16, 32]) : c'est l'effectif « Libre ».
    max_players: player_count,
    # ── Le cœur de cette recette ──────────────────────────────────────────────
    pool_seeding_mode: "pots",
    seeded_pot_count: pot_count,
    status: "open",
    date: Date.current + 14,
    place: "CACD2 — salle de ping-pong",
    registration_deadline: Date.current
  )

  # ── Les organisateurs, inscrits comme JOUEURS ───────────────────────────────
  # L'admin d'abord (il est `tournaments.user_id`, aucun drapeau nécessaire), puis
  # les co-organisateurs, qui portent le drapeau `co_organizer` SANS renoncer à
  # leur place : c'est ce que la colonne dédiée rend possible.
  tournament.tournament_users.create!(user: admin, role: "joueur", status: "approved")
  co_organizers.each do |person|
    tournament.tournament_users.create!(user: person, role: "joueur",
                                        status: "approved", co_organizer: true)
  end

  # ── Les joueurs de test ─────────────────────────────────────────────────────
  # De vrais prénoms/noms plutôt que « Joueur 1..22 » : l'app affiche partout
  # « Prénom N. » (User#short_name), et une liste de « Joueur 1 vs Joueur 9 » ne
  # permet pas de juger ce rendu. Quelques homonymes volontaires (deux Martin,
  # deux Bernard) pour voir l'initiale faire son travail de désambiguïsation.
  names = [
    %w[Léa Martin],      %w[Hugo Martin],     %w[Camille Bernard], %w[Théo Bernard],
    %w[Nathan Dubois],   %w[Chloé Thomas],    %w[Enzo Robert],     %w[Manon Richard],
    %w[Lucas Petit],     %w[Jade Durand],     %w[Louis Leroy],     %w[Emma Moreau],
    %w[Gabriel Simon],   %w[Alice Laurent],   %w[Raphaël Michel],  %w[Inès Garcia],
    %w[Adam Roux],       %w[Louise Fournier], %w[Ethan Girard],    %w[Rose Bonnet],
    %w[Sacha Lambert],   %w[Anna Fontaine]
  ]

  if fake_count > names.size
    puts "❌ #{fake_count} comptes fictifs demandés pour #{names.size} noms disponibles."
    return
  end

  # Mot de passe aléatoire par défaut (cf. l'en-tête) : personne n'a besoin de se
  # connecter en tant que joueur pour saisir les résultats, l'organisateur peut
  # tout saisir depuis son propre compte.
  shared_password = ENV["PLAYER_PASSWORD"].presence

  players = (1..fake_count).map do |i|
    first_name, last_name = names[i - 1]
    email = format("%s%02d@%s", email_prefix, i, email_domain)

    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.assign_attributes(
        password: shared_password || "#{SecureRandom.base58(24)}aA1!",
        confirmed_at: Time.current,
        first_name: first_name, last_name: last_name
      )
      user.save!
      user.create_profil!(first_name: first_name, last_name: last_name)
    end
    user
  end

  # Aucun `pot` n'est renseigné : tous les inscrits partent au chapeau général,
  # c'est l'organisateur qui les répartit depuis l'onglet Constitution.
  players.each do |player|
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
  end

  # ── On s'arrête ici : c'est l'admin qui remplit les chapeaux, puis lance ────
  # Le tournoi est complet, donc déjà passé en "closed" par le hook de
  # TournamentUser (`close_tournament_if_full`). `Tournament#startable?` accepte
  # `open?` OU `closed?` : le bouton « Lancer le tournoi » est donc bien proposé.
  tournament.reload

  puts "✅ « #{tournament_name} » créé"
  puts "   #{tournament.approved_players_count} joueurs · poules de #{players_in_pool} demandées"
  puts "   Statut          : #{tournament.status}#{' — startable' if tournament.startable?}"
  # pool_plan se calcule sur l'effectif inscrit : il annonce donc les tailles de
  # poules AVANT tout tirage. Seule la composition dépendra des chapeaux.
  puts "   Plan de poules  : #{tournament.pool_plan.inspect} (prévu)"
  puts "   Constitution    : #{tournament.seeding_mode} · #{tournament.pot_count} chapeaux · " \
       "#{tournament.pots.fetch(nil, []).size} joueurs au chapeau général (tous)"
  puts "   Poules          : pas encore tirées — remplir les chapeaux, PUIS « Lancer le tournoi »"
  puts "   Phase finale    : #{tournament.final_size} places pour " \
       "#{tournament.pool_count * 2} entrants attendus"
  puts "   Administrateur   : #{admin.email} (inscrit comme JOUEUR : il a ses propres matchs)"
  puts "   Co-organisateurs : #{co_organizers.map(&:email).join(', ').presence || '(aucun)'}"
  puts "                      → inscrits comme JOUEURS eux aussi (colonne co_organizer)"
  puts "   Comptes joueurs  : #{email_prefix}01..#{format('%02d', fake_count)}@#{email_domain}"
  puts "   Mot de passe     : #{shared_password ? 'PLAYER_PASSWORD (commun)' : 'aléatoire par compte (non communicable)'}"
  puts "   → /tournois/#{tournament.slug}"
  puts
  puts "ℹ️  Marche à suivre de la recette :"
  puts "   1. Onglet « Constitution » : placer 7 joueurs en chapeau 1, 7 en chapeau 2."
  puts "   2. « Lancer le tournoi » : chaque poule doit recevoir exactement un joueur"
  puts "      de chaque chapeau, les 11 restants comblant les poules les moins remplies."
  puts "   3. Les 3 poules de 3 se jouent avec un bye tournant : vérifier qu'il ne"
  puts "      rapporte ni victoire ni match joué au classement."
end

seed.call
