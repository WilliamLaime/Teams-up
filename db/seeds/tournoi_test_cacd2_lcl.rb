# ── Seed : « Tournoi test CACD2 x LCL » (Critérium Fédéral, 32 joueurs) ───────
# Tournoi de recette destiné à être joué EN PRODUCTION par des collègues : on
# monte la structure et les 32 inscrits, puis on s'arrête. Aucun score n'est
# saisi — c'est précisément ce qu'ils viennent tester.
#
# État obtenu : tournoi lancé (tirage au sort fait, 8 poules de 4 constituées),
# journée 1 de poules générée et VIDE. Les barrages, le tableau final et la
# consolante sont déjà visibles avec des cases « À déterminer » et se peupleront
# au fil des résultats.
#
# ── Lancement ────────────────────────────────────────────────────────────────
#   bin/rails runner db/seeds/tournoi_test_cacd2_lcl.rb
#
# En production sur Railway (le dossier db/ est bien dans l'image Docker) :
#   railway run bin/rails runner db/seeds/tournoi_test_cacd2_lcl.rb
#
# Idempotent : relancer ne recrée rien. Pour repartir de zéro :
#   RESET=1 bin/rails runner db/seeds/tournoi_test_cacd2_lcl.rb
#
# ── Variables d'environnement ────────────────────────────────────────────────
#   ADMIN_EMAIL      email de l'administrateur du tournoi (défaut : recherche
#                    « Antoine Lozach » par son profil)
#   CO_ORG_EMAILS    emails des co-organisateurs, séparés par des virgules
#                    (défaut : « Olivier Parinet » et « William Laimé »)
#   PLAYER_PASSWORD  mot de passe commun aux 32 comptes de test. Par défaut
#                    CHACUN reçoit un mot de passe aléatoire : ces comptes vivent
#                    en production, un mot de passe connu et deviné depuis le
#                    motif des emails permettrait de s'y connecter et de publier
#                    dans l'app sous une fausse identité. À ne renseigner que
#                    pour tester délibérément la vue « joueur ».
#   RESET=1          supprime le tournoi existant avant de le recréer
#
# ── Purge des comptes de test ────────────────────────────────────────────────
#   User.where("email LIKE 'cacd2lcl%@teamup-demo.fr'").destroy_all

# Tout le script vit dans un lambda : `return` y est licite (ce n'est pas le cas
# au niveau racine d'un fichier passé à `rails runner`), ce qui permet des gardes
# lisibles plutôt qu'une pyramide de `if`.
seed = lambda do
  tournament_name = "Tournoi test CACD2 x LCL"
  player_count    = 32
  email_domain    = "teamup-demo.fr"
  email_prefix    = "cacd2lcl"

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
    description: "Tournoi de test du format FFTT « Critérium Fédéral » : 8 poules de 4, " \
                 "barrages (2es contre 3es d'une autre poule), tableau final, consolante " \
                 "et matchs de classement — chaque place se joue. " \
                 "Les résultats sont à saisir librement : rien n'est joué au départ.",
    sport: sport,
    user: admin,
    format: "criterium_federal",
    players_per_pool: 4,
    # Explicite, même si 32 joueurs tombe déjà dans la variante standard : c'est
    # ce réglage qui garantit barrages + consolante plutôt qu'un tableau unique,
    # et on ne veut pas qu'un ajustement des seuils change la recette.
    final_phase_mode: "standard",
    max_players: player_count,
    status: "open",
    date: Date.current + 14,
    place: "CACD2 — salle de ping-pong",
    # Inscriptions closes : les 32 places sont pourvues, le tournoi est lancé.
    registration_deadline: Date.current
  )

  # ── Co-organisateurs ────────────────────────────────────────────────────────
  # Rôle exclusif de « joueur » (cf. TournamentUser::ROLES) : un co-organisateur
  # ne fait donc pas partie des 32 inscrits.
  co_organizers.uniq.each do |person|
    tournament.tournament_users.create!(user: person, role: "co_organisateur", status: "approved")
  end

  # ── Les 32 joueurs ──────────────────────────────────────────────────────────
  # De vrais prénoms/noms plutôt que « Joueur 1..32 » : l'app affiche partout
  # « Prénom N. » (User#short_name), et une liste de « Joueur 1 vs Joueur 17 » ne
  # permet pas de juger ce rendu. Quelques homonymes volontaires (deux Martin,
  # deux Bernard) pour voir l'initiale faire son travail de désambiguïsation.
  names = [
    %w[Léa Martin],      %w[Hugo Martin],     %w[Camille Bernard], %w[Théo Bernard],
    %w[Nathan Dubois],   %w[Chloé Thomas],    %w[Enzo Robert],     %w[Manon Richard],
    %w[Lucas Petit],     %w[Jade Durand],     %w[Louis Leroy],     %w[Emma Moreau],
    %w[Gabriel Simon],   %w[Alice Laurent],   %w[Raphaël Michel],  %w[Inès Garcia],
    %w[Tom Roux],        %w[Sarah David],     %w[Maxime Bertrand], %w[Clara Morel],
    %w[Adrien Fournier], %w[Louise Girard],   %w[Noah Bonnet],     %w[Zoé Dupont],
    %w[Malo Lambert],    %w[Anaïs Fontaine],  %w[Ethan Rousseau],  %w[Lina Vincent],
    %w[Arthur Muller],   %w[Nina Faure],      %w[Paul Chevalier],  %w[Rose Gauthier]
  ]

  # Mot de passe aléatoire par défaut (cf. l'en-tête) : personne n'a besoin de se
  # connecter en tant que joueur pour saisir les résultats, l'organisateur peut
  # tout saisir depuis son propre compte.
  shared_password = ENV["PLAYER_PASSWORD"].presence

  players = (1..player_count).map do |i|
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

  players.each do |player|
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
  end

  # ── Lancement ───────────────────────────────────────────────────────────────
  # Reproduit exactement TournamentsController#start (statut, tirage au sort, puis
  # génération du premier tour), à une différence près : le tirage est FIGÉ dans
  # l'ordre d'inscription au lieu d'être mélangé, pour que deux exécutions de
  # cette seed donnent les mêmes poules — une recette doit être reproductible.
  ActiveRecord::Base.transaction do
    tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    tournament.update!(status: "in_progress")
    TournamentEngine.for(tournament).next_round!
  end

  tournament.reload
  pending = TournamentMatch.joins(:tournament_round)
                           .where(tournament_rounds: { tournament_id: tournament.id })
                           .where(status: "pending", is_bye: false).count

  puts "✅ « #{tournament_name} » créé"
  puts "   #{player_count} joueurs · #{tournament.pool_count} poules de #{tournament.pool_size} · " \
       "Critérium Fédéral (variante standard)"
  # Les journées sont générées UNE PAR UNE par PoolBuilder : `pool_rounds.count`
  # vaut donc 1 à ce stade. Le total se déduit du round-robin — une poule de n
  # joueurs se joue en n-1 journées.
  puts "   Journée 1/#{tournament.pool_size - 1} générée : #{pending} match(s) à saisir"
  puts "   Administrateur   : #{admin.email}"
  puts "   Co-organisateurs : #{co_organizers.map(&:email).join(', ').presence || '(aucun)'}"
  puts "   Comptes joueurs  : #{email_prefix}01..#{player_count}@#{email_domain}"
  puts "   Mot de passe     : #{shared_password ? 'PLAYER_PASSWORD (commun)' : 'aléatoire par compte (non communicable)'}"
  puts "   → /tournois/#{tournament.slug}"
  puts
  puts "ℹ️  Rappel : `users.admin` n'ouvre que /admin. Les droits de gestion d'un"
  puts "   tournoi viennent de Tournament#organizer? (créateur OU co-organisateur),"
  puts "   d'où l'inscription explicite des co-organisateurs ci-dessus."
end

seed.call
