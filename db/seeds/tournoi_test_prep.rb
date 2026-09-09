# ── Seed : « Tournoi test préparation — CACD2 » (Critérium, 10 joueurs) ────────
# Un tournoi PRÊT À ÊTRE LANCÉ, mais pas lancé : c'est le seul état que les seeds
# existantes ne fournissaient pas à petit effectif (criterium_demo = 16 joueurs déjà
# lancé et joué, tournoi_test_impair = 17, tournoi_test_chapeaux = 25).
#
# ── À quoi il sert ───────────────────────────────────────────────────────────
#   • Juger le rendu de /tournois/:id AVANT lancement — notamment l'illustration
#     d'état posée à droite du titre (shared/_illu_tournoi_prep), et sa recoloration
#     dans les deux thèmes.
#   • Rejouer à volonté l'animation de tirage au sort : le bouton « Lancer le tournoi
#     & tirer au sort » de _start_panel passe par TournamentsController#start, qui
#     répond en Turbo Stream avec _draw_overlay. `RESET=1` remet le tournoi à zéro,
#     donc la séquence se rejoue autant de fois qu'on veut.
#
# ── Le plan de poules à 10 joueurs ───────────────────────────────────────────
# `players_per_pool` est laissé VIDE, exprès : les seuils du règlement FFTT
# s'appliquent alors (Tournament#criterium_pool_count_for → 2 poules jusqu'à 10
# inscrits), soit [5, 5]. Le renseigner à 4 — la seule autre valeur légale en
# Critérium avec 3 — court-circuiterait ces seuils (ceil(10/4) = 3 poules, [4,3,3]),
# ce qui est un cas déjà couvert par tournoi_test_impair.
#
# `final_phase_mode` reste nil pour la même raison : à 10 inscrits (≤ 16), le
# règlement déduit le mode « integral » — un SEUL tableau final, tout le monde
# dedans, ni barrages ni consolante. C'est justement la variante des petits
# effectifs, que les autres seeds (toutes en "standard") ne montrent jamais.
#
# ── Lancement ────────────────────────────────────────────────────────────────
#   bin/rails runner db/seeds/tournoi_test_prep.rb
#
# Idempotent : relancer ne recrée rien. Pour repartir de zéro :
#   RESET=1 bin/rails runner db/seeds/tournoi_test_prep.rb
#
# ── Variables d'environnement ────────────────────────────────────────────────
#   ADMIN_EMAIL      email de l'administrateur du tournoi (défaut : recherche
#                    « William Laimé » par son profil)
#   PLAYER_PASSWORD  mot de passe commun aux 9 comptes de test. Par défaut chacun
#                    reçoit un mot de passe aléatoire : inutile de se connecter en
#                    joueur, l'organisateur saisit tout depuis son compte.
#   OPEN=1           reforce le statut « open » après les inscriptions, pour voir le
#                    badge « Inscriptions ouvertes ». Sans lui, le 10e inscrit remplit
#                    le tournoi et le hook close_tournament_if_full le passe en
#                    « closed » — pas lancé pour autant (cf. plus bas).
#   RESET=1          supprime le tournoi existant avant de le recréer
#
# ── Purge des comptes de test ────────────────────────────────────────────────
# Ne touche QUE les 9 comptes fictifs, jamais l'admin (vrai compte) :
#   User.where("email LIKE 'prep%@teamup-demo.fr'").destroy_all

# Tout le script vit dans un lambda : `return` y est licite (ce n'est pas le cas au
# niveau racine d'un fichier passé à `rails runner`), ce qui permet des gardes
# plates plutôt qu'une pyramide de `if`.
seed = lambda do
  tournament_name = "Tournoi test préparation — CACD2"
  player_count    = 10
  # L'admin occupe l'une des 10 places : 9 comptes de test suffisent.
  fake_count      = player_count - 1
  email_domain    = "teamup-demo.fr"
  email_prefix    = "prep"

  # ── Résolution de l'administrateur ──────────────────────────────────────────
  # Recherche par PROFIL et non par User : `User#first_name` / `#last_name` ne sont
  # que des attr_accessor (utilisés à la création), les vrais noms vivent dans
  # `profils`.
  admin =
    if ENV["ADMIN_EMAIL"].present?
      User.find_by(email: ENV["ADMIN_EMAIL"])
    else
      Profil.where("first_name ILIKE ? AND last_name ILIKE ?", "William", "Laimé").first&.user
    end

  # Sans administrateur, pas de tournoi : `tournament.user` porte les droits de gestion,
  # donc le bouton « Lancer le tournoi » que cette seed sert justement à exercer.
  if admin.nil?
    puts "❌ Administrateur introuvable (« William Laimé » par défaut)."
    puts "   Relancer avec ADMIN_EMAIL=..."
    return
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
    description: "Tournoi de recette laissé AVANT lancement : 10 joueurs inscrits, aucune " \
                 "poule tirée. Sert à juger la page d'un tournoi en préparation et à rejouer " \
                 "l'animation du tirage au sort autant de fois que nécessaire.",
    sport: sport,
    user: admin,
    format: "criterium_federal",
    # players_per_pool et final_phase_mode volontairement absents : cf. l'en-tête,
    # on veut les seuils du règlement (2 poules de 5, phase finale « integral »).
    max_players: player_count,
    status: "open",
    # La date doit être dans le futur (validation date_cannot_be_in_the_past, on: :create).
    date: Date.current + 14,
    place: "CACD2 — salle de ping-pong",
    registration_deadline: Date.current + 7
  )

  # ── Les 9 joueurs de test ───────────────────────────────────────────────────
  # De vrais prénoms/noms plutôt que « Joueur 1..9 » : l'app affiche partout
  # « Prénom N. » (User#short_name), et deux Martin permettent de voir l'initiale
  # faire son travail de désambiguïsation — y compris dans l'overlay de tirage.
  names = [
    %w[Léa Martin],    %w[Hugo Martin],   %w[Camille Bernard],
    %w[Nathan Dubois], %w[Chloé Thomas],  %w[Enzo Robert],
    %w[Manon Richard], %w[Lucas Petit],   %w[Jade Durand]
  ]

  shared_password = ENV["PLAYER_PASSWORD"].presence

  players = (1..fake_count).map do |i|
    first_name, last_name = names[i - 1]
    email = "#{email_prefix}#{format('%02d', i)}@#{email_domain}"

    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.assign_attributes(
        # Le mot de passe doit satisfaire User::PASSWORD_REGEX (majuscule, chiffre,
        # symbole) : d'où le suffixe sur la partie aléatoire.
        password: shared_password || "#{SecureRandom.base58(24)}aA1!",
        # Devise :confirmable — sans ça, le compte ne peut pas se connecter.
        confirmed_at: Time.current,
        # first_name / last_name sont validés `on: :create` bien qu'ils ne soient pas
        # persistés sur users : il faut les passer à save!, puis créer le Profil.
        first_name: first_name, last_name: last_name
      )
      user.save!
      user.create_profil!(first_name: first_name, last_name: last_name)
    end
    user
  end

  # L'admin joue lui aussi, inscrit en PREMIER pour être facile à retrouver dans la
  # liste des inscrits pendant la recette. C'est possible parce que l'admin d'un
  # tournoi est `tournaments.user_id` et non un rôle de `tournament_users`.
  tournament.tournament_users.create!(user: admin, role: "joueur", status: "approved")

  players.each do |player|
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
  end

  # ── On s'arrête ici : c'est l'admin qui lance ───────────────────────────────
  # Le tournoi est complet, donc déjà passé en "closed" par le hook de TournamentUser
  # (`close_tournament_if_full`). Ce n'est PAS un lancement : `Tournament#startable?`
  # accepte `open?` OU `closed?`, le bouton « Lancer le tournoi » reste donc proposé,
  # et l'illustration de préparation reste affichée (même condition dans show.html.erb).
  #
  # OPEN=1 rouvre les inscriptions pour voir aussi le badge vert. update_column plutôt
  # que update! : on contourne délibérément le hook qui vient de fermer le tournoi.
  if ENV["OPEN"] == "1"
    tournament.update_column(:status, "open")
    puts "ℹ️  OPEN=1 : statut reforcé à « open » malgré les 10/10 places pourvues."
  end

  tournament.reload

  puts "✅ « #{tournament_name} » créé"
  puts "   #{player_count} joueurs (admin inclus) · Critérium Fédéral"
  puts "   Statut          : #{tournament.status}#{' — startable' if tournament.startable?}"
  # pool_plan se calcule sur l'effectif inscrit : il annonce les TAILLES de poules
  # avant tout tirage. Seule leur composition dépendra du tirage de l'admin.
  puts "   Plan de poules  : #{tournament.pool_plan.inspect} (prévu, pas encore tiré)"
  puts "   Phase finale    : mode #{tournament.criterium_mode} · #{tournament.final_size} places"
  puts "   Administrateur  : #{admin.email} (inscrit comme JOUEUR)"
  puts "   Comptes joueurs : #{email_prefix}01..#{format('%02d', fake_count)}@#{email_domain} (+ l'admin)"
  puts "   Mot de passe    : #{shared_password ? 'PLAYER_PASSWORD (commun)' : 'aléatoire par compte'}"
  puts "   → /tournois/#{tournament.slug}"
  puts
  puts "ℹ️  Tournoi NON lancé : cliquer « Lancer le tournoi & tirer au sort » depuis"
  puts "   l'app pour voir l'animation du tirage. RESET=1 sur cette seed pour rejouer."
end

seed.call
