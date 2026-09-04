# ── Seed : « Tournoi test effectif impair — CACD2 » (Critérium, 17 joueurs) ────
# Variante volontairement BANCALE de db/seeds/tournoi_test_cacd2_lcl.rb (32 joueurs,
# 8 poules de 4 — un cas parfaitement pair). Ici l'effectif est IMPAIR et les poules
# sont de 3, ce qui fabrique une POULE DE 2 : le cas que le code anticipe explicitement
# (cf. CriteriumFlow#barrage_pairs, PoolStandings) sans qu'il ait jamais été joué en vrai.
#
# 17 joueurs en poules de 3 → ceil(17 / 3) = 6 poules → Tournament#balanced_plan répartit
# en [3, 3, 3, 3, 3, 2]. Une seule poule de 2, c'est ce qu'on vient observer.
#
# ── Ce que ce tournoi sert à mettre à l'épreuve ───────────────────────────────
#   • Le classement d'une poule de 2 (un seul match, donc un seul vainqueur).
#   • Une poule qui joue MOINS de journées que les autres : le round-robin d'une poule
#     de 3 se déroule en 3 journées (bye tournant), celui d'une poule de 2 en UNE. La
#     poule de 2 n'a donc aucun match en journées 2 et 3 — cf. PoolBuilder, qui saute
#     les poules à court de journées (`next if pairs.nil?`).
#   • Les byes des poules de 3, qui doivent rester HORS du classement (PoolStandings).
#   • Au barrage, le 2e de la poule de 2 n'a pas de 3e en face : bye, et il monte au
#     tableau final d'office (CriteriumFlow#barrage_pairs).
#   • Un tableau final dimensionné sur 6 poules × 2 = 12 entrants, donc PAS une puissance
#     de 2 : le tableau est de 16 avec 4 byes. Les 8 poules de 4 de l'autre seed, qui
#     donnent 16 entrants pile, n'exercent jamais ce calcul.
#
# L'administrateur est AUSSI inscrit comme joueur : il se verra donc dans une poule et
# aura ses propres rencontres à jouer, en plus de gérer le tournoi. C'est possible parce
# que l'admin d'un tournoi est `tournaments.user_id` et non un rôle de `tournament_users` :
# rien n'empêche le créateur d'avoir par ailleurs une inscription « joueur ». Les
# CO-organisateurs, eux, ne peuvent pas jouer — l'index unique (tournoi, user) n'autorise
# qu'un rôle par personne, et le leur est déjà pris.
#
# État obtenu : tournoi PRÊT À ÊTRE LANCÉ, mais PAS lancé. Les 17 inscriptions sont
# posées (l'admin + 16 comptes de test) et le tournoi est complet, donc `closed` —
# aucune poule n'existe encore.
# C'est l'ADMIN qui clique « Lancer le tournoi » depuis l'app : le tirage au sort réel
# (mélangé, cf. TournamentsController#start) et la génération des poules font ainsi
# partie de la recette, au lieu d'être faits dans le dos par cette seed.
#
# Corollaire assumé : le tirage n'est PAS reproductible d'un lancement à l'autre — c'est
# `shuffle` qui décide. Seules les TAILLES de poules sont garanties ([3,3,3,3,3,2]),
# jamais leur composition. C'est ce qu'on veut vérifier.
#
# ── Lancement ────────────────────────────────────────────────────────────────
#   bin/rails runner db/seeds/tournoi_test_impair.rb
#
# En production sur Railway, DANS le conteneur du service web :
#   railway ssh --service Teams-up bin/rails runner db/seeds/tournoi_test_impair.rb
#
# ⚠️ Et NON `railway run` : celui-ci exécute la commande sur la machine locale en y
# injectant les variables du service. Or `DATABASE_URL` pointe sur un hôte
# `*.railway.internal`, qui n'est joignable que depuis le réseau Railway — la
# connexion échoue donc depuis un poste de dev. `railway ssh` exécute bel et bien
# dans le conteneur, où cet hôte résout. Corollaire : le fichier doit être DÉPLOYÉ
# (il vient de l'image, pas du poste local).
#
# Idempotent : relancer ne recrée rien. Pour repartir de zéro :
#   RESET=1 bin/rails runner db/seeds/tournoi_test_impair.rb
#
# ── Variables d'environnement ────────────────────────────────────────────────
#   ADMIN_EMAIL      email de l'administrateur du tournoi (défaut : recherche
#                    « Antoine Lozach » par son profil)
#   CO_ORG_EMAILS    emails des co-organisateurs, séparés par des virgules
#                    (défaut : « Olivier Parinet » et « William Laimé »)
#   PLAYER_PASSWORD  mot de passe commun aux 17 comptes de test. Par défaut CHACUN
#                    reçoit un mot de passe aléatoire : ces comptes vivent en
#                    production, un mot de passe connu et deviné depuis le motif des
#                    emails permettrait de s'y connecter et de publier dans l'app sous
#                    une fausse identité. À ne renseigner que pour tester
#                    délibérément la vue « joueur ».
#   RESET=1          supprime le tournoi existant avant de le recréer
#   START=1          lance le tournoi au lieu de le laisser à l'admin (tirage FIGÉ
#                    dans l'ordre d'inscription, donc reproductible). Réservé à la
#                    vérification locale du plan de poules — en production, laisser
#                    l'admin lancer lui-même depuis l'app, c'est l'objet de la recette.
#
# ── Purge des comptes de test ────────────────────────────────────────────────
# Ne touche QUE les 16 comptes fictifs : l'admin est un vrai compte, il joue mais ne
# doit évidemment pas être supprimé avec la recette.
#   User.where("email LIKE 'impair%@teamup-demo.fr'").destroy_all

# Tout le script vit dans un lambda : `return` y est licite (ce n'est pas le cas
# au niveau racine d'un fichier passé à `rails runner`), ce qui permet des gardes
# lisibles plutôt qu'une pyramide de `if`.
seed = lambda do
  tournament_name = "Tournoi test effectif impair — CACD2"
  player_count    = 17 # impair, et 17 = 3+3+3+3+3+2 en poules de 3
  # L'admin occupe l'une des 17 places : 16 comptes de test suffisent.
  fake_count      = player_count - 1
  players_in_pool = 3
  email_domain    = "teamup-demo.fr"
  email_prefix    = "impair"

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
  # Les co-organisateurs déclarés : par email si fournis, sinon par nom. William
  # Laimé y figure DÉLIBÉRÉMENT — cf. la note en fin de script : être admin de
  # l'application ne donne aucun droit sur un tournoi qu'on ne co-organise pas.
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
    description: "Tournoi de recette à effectif IMPAIR : 17 joueurs en poules de 3, ce qui " \
                 "donne 5 poules de 3 et une poule de 2. Sert à vérifier le comportement de " \
                 "la petite poule — classement, journées manquantes, bye au barrage — et un " \
                 "tableau final dimensionné sur 12 entrants. " \
                 "Les résultats sont à saisir librement : rien n'est joué au départ.",
    sport: sport,
    user: admin,
    format: "criterium_federal",
    # 3 (et non 4) : c'est ce réglage qui fabrique la poule de 2 sur 17 inscrits.
    # Tournament n'accepte que 3 ou 4 en Critérium (cf. la validation du modèle).
    players_per_pool: players_in_pool,
    # Explicite : à 17 joueurs les seuils du règlement donneraient déjà "standard",
    # mais on ne veut pas qu'un ajustement de ces seuils change la recette (on tient
    # aux barrages et à la consolante, c'est là que la poule de 2 se voit).
    final_phase_mode: "standard",
    # 17 n'est pas un preset (PLAYER_COUNTS = [8, 16, 32]) : c'est l'effectif « Libre »,
    # qui autorise n'importe quel entier. C'est tout l'objet de cette seed.
    max_players: player_count,
    status: "open",
    date: Date.current + 14,
    place: "CACD2 — salle de ping-pong",
    # Inscriptions closes : les 17 places sont pourvues, le tournoi est lancé.
    registration_deadline: Date.current
  )

  # ── Co-organisateurs ────────────────────────────────────────────────────────
  # Rôle exclusif de « joueur » (cf. TournamentUser::ROLES) : un co-organisateur
  # ne fait donc pas partie des 17 inscrits.
  co_organizers.uniq.each do |person|
    tournament.tournament_users.create!(user: person, role: "co_organisateur", status: "approved")
  end

  # ── Les 16 joueurs de test ──────────────────────────────────────────────────
  # De vrais prénoms/noms plutôt que « Joueur 1..16 » : l'app affiche partout
  # « Prénom N. » (User#short_name), et une liste de « Joueur 1 vs Joueur 9 » ne
  # permet pas de juger ce rendu. Quelques homonymes volontaires (deux Martin,
  # deux Bernard) pour voir l'initiale faire son travail de désambiguïsation.
  names = [
    %w[Léa Martin],      %w[Hugo Martin],     %w[Camille Bernard], %w[Théo Bernard],
    %w[Nathan Dubois],   %w[Chloé Thomas],    %w[Enzo Robert],     %w[Manon Richard],
    %w[Lucas Petit],     %w[Jade Durand],     %w[Louis Leroy],     %w[Emma Moreau],
    %w[Gabriel Simon],   %w[Alice Laurent],   %w[Raphaël Michel],  %w[Inès Garcia]
  ]

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

  # L'admin joue lui aussi : inscrit en PREMIER pour qu'il soit facile à retrouver dans
  # la liste des inscrits pendant la recette.
  tournament.tournament_users.create!(user: admin, role: "joueur", status: "approved")

  players.each do |player|
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
  end

  # ── On s'arrête ici : c'est l'admin qui lance ───────────────────────────────
  # Le tournoi est complet, donc déjà passé en "closed" par le hook de
  # TournamentUser (`close_tournament_if_full`). `Tournament#startable?` accepte
  # `open?` OU `closed?` : le bouton « Lancer le tournoi » est donc bien proposé à
  # l'admin, et c'est LUI qui déclenche le vrai tirage au sort (mélangé) et la
  # génération des poules.
  #
  # START=1 fait le travail à sa place, avec un tirage FIGÉ dans l'ordre d'inscription
  # (donc reproductible) : réservé à la vérification locale du plan de poules.
  if ENV["START"] == "1"
    puts "⚠️  START=1 : le tournoi est lancé par la seed, avec un tirage FIGÉ."
    ActiveRecord::Base.transaction do
      tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
        tu.update_column(:draw_order, index)
      end
      tournament.update!(status: "in_progress")
      TournamentEngine.for(tournament).next_round!
    end
  end

  tournament.reload
  matches = TournamentMatch.joins(:tournament_round).where(tournament_rounds: { tournament_id: tournament.id })
  pending = matches.where(status: "pending", is_bye: false).count
  byes    = matches.where(is_bye: true).count
  # Tant que le tirage n'a pas eu lieu, tout le monde est en pool NULL : ce groupe-là
  # n'est pas une poule, on l'écarte pour ne pas annoncer une « poule de 17 ».
  sizes   = tournament.tournament_users.players.approved.where.not(pool: nil)
                      .group(:pool).count.values.sort.reverse

  puts "✅ « #{tournament_name} » créé"
  puts "   #{player_count} joueurs (impair, admin inclus) · poules de #{players_in_pool} demandées"
  puts "   Statut          : #{tournament.status}#{' — startable' if tournament.startable?}"
  # pool_plan se calcule sur l'effectif inscrit : il annonce donc les tailles de poules
  # AVANT tout tirage. Seule la composition dépendra du tirage de l'admin.
  puts "   Plan de poules  : #{tournament.pool_plan.inspect} (prévu)#{" — réel : #{sizes.inspect}" if sizes.any?}"
  if tournament.pool_rounds.any?
    puts "   Journées        : #{tournament.pool_rounds.count} (une poule de 3 se joue en 3, " \
         "une poule de 2 en 1 seule)"
    puts "   #{pending} match(s) à saisir · #{byes} bye(s)"
  else
    puts "   Poules          : pas encore tirées — à l'admin de cliquer « Lancer le tournoi »"
  end
  puts "   Phase finale    : #{tournament.final_size} places pour " \
       "#{tournament.pool_count * 2} entrants attendus"
  puts "   Administrateur   : #{admin.email} (inscrit comme JOUEUR : il a ses propres matchs)"
  puts "   Co-organisateurs : #{co_organizers.map(&:email).join(', ').presence || '(aucun)'}"
  puts "   Comptes joueurs  : #{email_prefix}01..#{fake_count}@#{email_domain} (+ l'admin)"
  puts "   Mot de passe     : #{shared_password ? 'PLAYER_PASSWORD (commun)' : 'aléatoire par compte (non communicable)'}"
  puts "   → /tournois/#{tournament.slug}"
  puts
  puts "ℹ️  Rappel : `users.admin` n'ouvre que /admin. Les droits de gestion d'un"
  puts "   tournoi viennent de Tournament#organizer? (créateur OU co-organisateur),"
  puts "   d'où l'inscription explicite des co-organisateurs ci-dessus."
end

seed.call
