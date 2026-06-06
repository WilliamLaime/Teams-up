require "test_helper"

# Tests pour MatchReminderJob
# Ce job envoie un email de rappel à chaque participant approuvé d'un match
# 24h avant le début du match. Il est planifié à la création du match.
class MatchReminderJobTest < ActiveJob::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  # Réinitialise la boîte mail de test avant chaque test
  # pour éviter que les emails d'un test précédent ne polluent le suivant.
  setup do
    ActionMailer::Base.deliveries.clear
  end

  # Nettoyage complet de la base après chaque test
  # pour éviter les conflits de contraintes FK entre tests.
  teardown { teardown_db }

  # ── CAS NOMINAL ──────────────────────────────────────────────────────────────

  # Vérifie que le job s'exécute sans erreur pour un match futur
  # avec des participants approuvés, et qu'il déclenche bien des emails.
  test "s'exécute sans erreur pour un match futur avec des joueurs inscrits" do
    # Création d'un organisateur et d'un joueur
    organizer = create_test_user(email: "orga@test.com", first_name: "Orga", last_name: "Test")
    player    = create_test_user(email: "player@test.com", first_name: "Player", last_name: "Test")

    # On réutilise le sport déjà créé par les fixtures (name: "Football", slug: "football")
    # pour éviter une violation de contrainte d'unicité sur name/slug.
    sport = sports(:one)

    # Le match est dans 25 heures → le rappel 24h avant est encore pertinent
    future_date = 25.hours.from_now
    match = Match.new(
      user:            organizer,
      sport:           sport,
      title:           "Match test rappel",
      date:            future_date.to_date,
      time:            future_date.strftime("%H:%M"),
      player_left:     5,
      level:           "Tout niveau",
      place:           "Paris",
      validation_mode: "automatic",
      visibility:      "public"
    )
    # On sauvegarde sans validation pour éviter la contrainte "30 min dans le futur"
    # qui peut bloquer en cas de lag dans les tests
    match.save!(validate: false)

    # Inscription de l'organisateur et du joueur comme "approuvés"
    MatchUser.create!(match: match, user: organizer, status: "approved", role: "organisateur")
    MatchUser.create!(match: match, user: player,    status: "approved", role: "joueur")

    # Le job doit s'exécuter sans exception (perform_now = synchrone)
    assert_nothing_raised do
      MatchReminderJob.perform_now(match.id)
    end

    # Le job planifie les emails via deliver_later → ils restent dans la queue
    # On vérifie qu'il a bien enfilé 2 mails (un par participant)
    assert_equal 2, enqueued_jobs.count { |j| j[:job] == ActionMailer::MailDeliveryJob }
  end

  # ── CAS LIMITE : MATCH SANS JOUEURS INSCRITS ────────────────────────────────

  # Vérifie que le job ne plante pas si le match n'a aucun participant.
  # Comportement attendu : il tourne sans erreur et n'envoie aucun email.
  test "ne plante pas si aucun joueur approuvé n'est inscrit" do
    organizer = create_test_user(email: "orga2@test.com", first_name: "Orga2", last_name: "Test")
    # Réutilise le sport de la fixture pour éviter les violations d'unicité
    sport = sports(:one)

    future_date = 25.hours.from_now
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       "Match sans joueurs",
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      player_left: 2,
      level:       "Tout niveau",
      place:       "Lyon",
      visibility:  "public"
    )
    match.save!(validate: false)

    # Aucun MatchUser → le job doit finir proprement sans rien envoyer
    assert_nothing_raised do
      MatchReminderJob.perform_now(match.id)
    end

    # Aucun email ne doit avoir été enfilé
    mail_jobs = enqueued_jobs.count { |j| j[:job] == ActionMailer::MailDeliveryJob }
    assert_equal 0, mail_jobs
  end

  # ── CAS D'ERREUR : MATCH INEXISTANT ─────────────────────────────────────────

  # Vérifie que le job gère silencieusement un match supprimé entre la planification
  # et l'exécution du job. Il ne doit pas lever d'exception ActiveRecord::RecordNotFound.
  test "ne plante pas si le match n'existe pas (retour anticipé silencieux)" do
    # On passe un id qui n'existe pas en base
    fake_match_id = 999_999_999

    # Le job utilise find_by (pas find) → retourne nil au lieu de lever une exception
    assert_nothing_raised do
      MatchReminderJob.perform_now(fake_match_id)
    end

    # Aucun email ne doit avoir été enfilé
    mail_jobs = enqueued_jobs.count { |j| j[:job] == ActionMailer::MailDeliveryJob }
    assert_equal 0, mail_jobs
  end

  # ── CAS LIMITE : MATCH DÉJÀ COMMENCÉ ────────────────────────────────────────

  # Vérifie que le job ne renvoie pas de rappel si le match a déjà eu lieu
  # (la queue était en retard par exemple). Comportement attendu : retour anticipé.
  test "ne renvoie pas de rappel si le match est déjà passé" do
    organizer = create_test_user(email: "orga3@test.com", first_name: "Orga3", last_name: "Test")
    player    = create_test_user(email: "player3@test.com", first_name: "Player3", last_name: "Test")
    # Réutilise le sport de la fixture pour éviter les violations d'unicité
    sport = sports(:one)

    # Match passé d'il y a 2 heures
    past_date = 2.hours.ago
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       "Match passé",
      date:        past_date.to_date,
      time:        past_date.strftime("%H:%M"),
      player_left: 3,
      level:       "Tout niveau",
      place:       "Marseille",
      visibility:  "public"
    )
    match.save!(validate: false)

    MatchUser.create!(match: match, user: organizer, status: "approved", role: "organisateur")
    MatchUser.create!(match: match, user: player,    status: "approved", role: "joueur")

    assert_nothing_raised do
      MatchReminderJob.perform_now(match.id)
    end

    # Aucun email ne doit avoir été enfilé car le match est déjà passé
    mail_jobs = enqueued_jobs.count { |j| j[:job] == ActionMailer::MailDeliveryJob }
    assert_equal 0, mail_jobs
  end
end
