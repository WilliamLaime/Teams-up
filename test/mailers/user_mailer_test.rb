require "test_helper"

# Tests pour UserMailer
# Ce mailer gère tous les emails transactionnels liés aux actions utilisateurs :
# rejoindre un match, statut d'inscription, annulation, quitter, avis, création,
# invitation équipe, demande d'ami, rappel 24h et modification de match.
class UserMailerTest < ActionMailer::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  # Réinitialise la boîte mail et bascule en mode test avant chaque test
  setup do
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
  end

  teardown { teardown_db }

  # Helper : crée un match futur sans valider les règles métier.
  # Pour les tests mailer, seules les données du mail importent.
  # On utilise sports(:one) (fixture Football) pour éviter les violations d'unicité
  # sur les colonnes name et slug de la table sports.
  def build_match(organizer:, title: "Match test")
    sport       = sports(:one)
    future_date = 25.hours.from_now
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       title,
      date:        future_date.to_date,
      time:        future_date.strftime("%H:%M"),
      player_left: 5,
      level:       "Tout niveau",
      place:       "Paris",
      visibility:  "public"
    )
    match.save!(validate: false)
    match
  end

  # 1. match_joined
  # Vérifie que l'email "un joueur a rejoint ton match" est envoyé à l'organisateur
  # avec le bon sujet contenant le nom du joueur.
  test "match_joined envoie l'email a l'organisateur avec le bon sujet" do
    organizer = create_test_user(email: "orga@mailer.com",   first_name: "Alice",  last_name: "Orga")
    player    = create_test_user(email: "player@mailer.com", first_name: "Bob",    last_name: "Player")
    match     = build_match(organizer: organizer)

    email = UserMailer.match_joined(match, player, status: "approved")

    # L'email doit être adressé à l'organisateur
    assert_emails 1 do
      email.deliver_now
    end
    assert_equal [organizer.email], email.to
    # Le sujet doit mentionner le nom du joueur
    assert_includes email.subject, player.display_name
  end

  # 2a. match_status_changed (accepté)
  # Vérifie que l'email "ta demande a été acceptée" est envoyé au joueur
  # avec un sujet positif contenant le titre du match.
  test "match_status_changed accepte envoie l'email au joueur avec le bon sujet" do
    organizer  = create_test_user(email: "orga2@mailer.com",   first_name: "Alice",  last_name: "Orga")
    player     = create_test_user(email: "player2@mailer.com", first_name: "Bob",    last_name: "Player")
    match      = build_match(organizer: organizer, title: "Tennis du dimanche")
    match_user = MatchUser.create!(match: match, user: player, status: "approved", role: "joueur")

    email = UserMailer.match_status_changed(match_user, accepted: true)

    assert_equal [player.email], email.to
    # Le sujet doit indiquer une acceptation et le titre du match
    assert_includes email.subject, match.title
    assert_includes email.subject, "accept"
  end

  # 2b. match_status_changed (refusé)
  # Vérifie que l'email "ta demande a été refusée" contient le bon sujet
  # sans le mot "accepté".
  test "match_status_changed refuse envoie l'email au joueur avec le bon sujet" do
    organizer  = create_test_user(email: "orga3@mailer.com",   first_name: "Alice",  last_name: "Orga")
    player     = create_test_user(email: "player3@mailer.com", first_name: "Bob",    last_name: "Player")
    match      = build_match(organizer: organizer, title: "Basket nocturne")
    match_user = MatchUser.create!(match: match, user: player, status: "rejected", role: "joueur")

    email = UserMailer.match_status_changed(match_user, accepted: false)

    assert_equal [player.email], email.to
    assert_includes email.subject, match.title
    # Le sujet ne doit pas dire "accepté" pour un refus
    assert_not_includes email.subject.downcase, "accept"
  end

  # 3. match_cancelled
  # Vérifie que l'email d'annulation est envoyé au bon joueur
  # avec le titre du match dans le sujet.
  test "match_cancelled envoie l'email au joueur avec le bon sujet" do
    organizer = create_test_user(email: "orga4@mailer.com",   first_name: "Alice",  last_name: "Orga")
    player    = create_test_user(email: "player4@mailer.com", first_name: "Bob",    last_name: "Player")
    match     = build_match(organizer: organizer, title: "Rugby du samedi")

    email = UserMailer.match_cancelled(match, player)

    assert_equal [player.email], email.to
    assert_includes email.subject, match.title
    assert_includes email.subject.downcase, "annul"
  end

  # 3b. match_cancelled_async
  # Vérifie la version asynchrone (avec scalaires) du mail d'annulation.
  # Elle reçoit des String/Date au lieu d'AR objects pour éviter les problèmes
  # de désérialisation GlobalID quand le match est déjà supprimé.
  test "match_cancelled_async envoie l'email avec les donnees scalaires" do
    email = UserMailer.match_cancelled_async(
      user_email:     "async@mailer.com",
      match_title:    "Match scalaire",
      match_date:     Date.tomorrow,
      match_time_str: "18h30",
      venue_name:     "Stade test",
      venue_city:     "Nice",
      organizer_name: "Charlie Orga"
    )

    assert_equal ["async@mailer.com"], email.to
    assert_includes email.subject, "Match scalaire"
    assert_includes email.subject.downcase, "annul"
  end

  # 4. match_player_left
  # Vérifie que l'email "un joueur a quitté ton match" est envoyé à l'organisateur
  # avec le nom du joueur dans le sujet.
  test "match_player_left envoie l'email a l'organisateur avec le bon sujet" do
    organizer = create_test_user(email: "orga5@mailer.com",   first_name: "Alice",  last_name: "Orga")
    player    = create_test_user(email: "player5@mailer.com", first_name: "David",  last_name: "Player")
    match     = build_match(organizer: organizer)

    email = UserMailer.match_player_left(match, player)

    assert_equal [organizer.email], email.to
    assert_includes email.subject, player.display_name
    assert_includes email.subject.downcase, "quitt"
  end

  # 5. avis_received
  # Vérifie que l'email "tu as reçu un avis" est envoyé au joueur noté
  # avec le nom du reviewer dans le sujet.
  # Le modèle Avis a des validations strictes :
  #   - reviewer et reviewed_user doivent avoir participé au match
  #   - le match doit être terminé (passé)
  # On bypasse ces validations avec save!(validate: false) car on teste
  # uniquement que le mailer envoie bien l'email.
  test "avis_received envoie l'email au joueur note avec le bon sujet" do
    reviewer = create_test_user(email: "reviewer@mailer.com", first_name: "Eve",   last_name: "Rev")
    reviewed = create_test_user(email: "reviewed@mailer.com", first_name: "Frank", last_name: "Rev")
    match    = build_match(organizer: reviewer)

    # Avis.create! exige : match terminé + les deux users participants
    # On bypasse les validations métier car le sujet du test est le mailer, pas le modèle Avis
    avis = Avis.new(
      reviewer:      reviewer,
      reviewed_user: reviewed,
      match:         match,
      rating:        4
    )
    avis.save!(validate: false)

    email = UserMailer.avis_received(avis)

    assert_equal [reviewed.email], email.to
    assert_includes email.subject, reviewer.display_name
  end

  # 6. match_created
  # Vérifie que l'email de confirmation de création de match est envoyé
  # à l'organisateur avec le titre du match dans le sujet.
  test "match_created envoie l'email a l'organisateur avec le bon sujet" do
    organizer = create_test_user(email: "orga6@mailer.com", first_name: "Grace", last_name: "Orga")
    match     = build_match(organizer: organizer, title: "Badminton matinal")

    email = UserMailer.match_created(match)

    assert_equal [organizer.email], email.to
    assert_includes email.subject, match.title
    assert_includes email.subject.downcase, "cr"
  end

  # 7. match_reminder
  # Vérifie que l'email de rappel 24h est envoyé au participant
  # avec le titre du match dans le sujet.
  test "match_reminder envoie l'email au participant avec le bon sujet" do
    organizer = create_test_user(email: "orga7@mailer.com",   first_name: "Hank",  last_name: "Orga")
    player    = create_test_user(email: "player7@mailer.com", first_name: "Irene", last_name: "Player")
    match     = build_match(organizer: organizer, title: "Natation du matin")

    email = UserMailer.match_reminder(match, player)

    assert_equal [player.email], email.to
    assert_includes email.subject, match.title
    # Le sujet doit contenir "Rappel" pour indiquer l'urgence
    assert_includes email.subject, "Rappel"
  end

  # 8. match_modified
  # Vérifie que l'email "le match a été modifié" est envoyé au participant
  # avec le titre du match dans le sujet.
  test "match_modified envoie l'email au participant avec le bon sujet" do
    organizer = create_test_user(email: "orga8@mailer.com",   first_name: "Jack",  last_name: "Orga")
    player    = create_test_user(email: "player8@mailer.com", first_name: "Kim",   last_name: "Player")
    match     = build_match(organizer: organizer, title: "Golf du jeudi")

    email = UserMailer.match_modified(match, player, changes: ["la date", "l'heure"])

    assert_equal [player.email], email.to
    assert_includes email.subject, match.title
    assert_includes email.subject.downcase, "modifi"
  end

  # 9. team_invitation_received
  # Vérifie que l'email d'invitation à rejoindre une équipe est envoyé à l'invité
  # avec le nom de l'inviteur et le nom de l'équipe dans le sujet.
  test "team_invitation_received envoie l'email a l'invite avec le bon sujet" do
    captain = create_test_user(email: "captain@mailer.com", first_name: "Lena", last_name: "Cap")
    invitee = create_test_user(email: "invitee@mailer.com", first_name: "Mike", last_name: "Inv")

    team = Team.create!(name: "Les Aigles", captain: captain)
    invitation = TeamInvitation.create!(
      team:    team,
      inviter: captain,
      invitee: invitee,
      status:  "pending"
    )

    email = UserMailer.team_invitation_received(invitation)

    assert_equal [invitee.email], email.to
    assert_includes email.subject, captain.display_name
    assert_includes email.subject, team.name
  end

  # 10a. friendship_decision (acceptée)
  # Vérifie que l'email "ta demande d'ami a été acceptée" est envoyé à l'expéditeur
  # avec le nom du destinataire dans le sujet.
  test "friendship_decision acceptee envoie l'email a l'expediteur" do
    sender   = create_test_user(email: "sender@mailer.com",   first_name: "Nina",  last_name: "Send")
    receiver = create_test_user(email: "receiver@mailer.com", first_name: "Oscar", last_name: "Recv")

    email = UserMailer.friendship_decision(sender, receiver, accepted: true)

    assert_equal [sender.email], email.to
    assert_includes email.subject, receiver.display_name
    assert_includes email.subject.downcase, "accept"
  end

  # 10b. friendship_decision (refusée)
  # Vérifie que l'email "ta demande d'ami a été refusée" ne contient pas "accepté".
  test "friendship_decision refusee envoie l'email a l'expediteur avec bon sujet" do
    sender   = create_test_user(email: "sender2@mailer.com",   first_name: "Paul",   last_name: "Send")
    receiver = create_test_user(email: "receiver2@mailer.com", first_name: "Quinn",  last_name: "Recv")

    email = UserMailer.friendship_decision(sender, receiver, accepted: false)

    assert_equal [sender.email], email.to
    assert_includes email.subject, receiver.display_name
    assert_not_includes email.subject.downcase, "accept"
  end
end
