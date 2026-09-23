require "test_helper"

# Tests de ChatMessageNotifier — déclenché par Message#notify_recipients.
#
# Règles vérifiées, pour les 4 types de chat :
#   - chaque destinataire (jamais l'expéditeur) reçoit une notification dans la
#     cloche et un mail est programmé à +3 min ;
#   - plusieurs messages d'affilée n'ouvrent QU'UNE fenêtre : 1 notification,
#     1 job, quel que soit le nombre de lignes ;
#   - seuls les participants qui ont accès au chat sont notifiés.
class ChatMessageNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  teardown { teardown_db }

  setup do
    @alice = create_test_user(email: "notif-alice@example.com", first_name: "Alice", last_name: "Martin")
    @bob   = create_test_user(email: "notif-bob@example.com", first_name: "Bob", last_name: "Durand")
  end

  def chat_notifications_for(user)
    Notification.where(user: user, notif_type: ChatMessageNotifier::NOTIF_TYPE)
  end

  def digest_jobs
    enqueued_jobs.select { |job| job["job_class"] == "ChatEmailDigestJob" }
  end

  # ── Conversation privée ────────────────────────────────────────────────────

  test "3 messages privés d'affilée = 1 notification et 1 mail programmé" do
    conversation = PrivateConversation.between(@alice, @bob)

    3.times { |i| conversation.messages.create!(user: @alice, content: "Ligne #{i}") }

    assert_equal 1, digest_jobs.size, "Un seul mail doit être programmé pour la fenêtre"
    assert_equal 1, chat_notifications_for(@bob).count
    assert_equal 0, chat_notifications_for(@alice).count, "L'expéditeur n'est pas notifié"

    notification = chat_notifications_for(@bob).first
    assert_equal "Alice Martin t'a envoyé un message", notification.message
    assert_equal "/users/#{@alice.id}/profil?open_chat=#{conversation.id}", notification.link
    assert_equal @alice, notification.actor
  end

  test "le mail est programmé 3 min après le premier message" do
    conversation = PrivateConversation.between(@alice, @bob)

    freeze_time do
      conversation.messages.create!(user: @alice, content: "Salut")
      assert_in_delta ChatEmailDigest::WINDOW.from_now.to_f, digest_jobs.first["scheduled_at"].to_time.to_f, 1
    end
  end

  test "une nouvelle fenêtre remplace la notification non lue au lieu d'en empiler une" do
    conversation = PrivateConversation.between(@alice, @bob)
    conversation.messages.create!(user: @alice, content: "Salut")

    # Fin de la 1re fenêtre (ce que fait ChatEmailDigestJob)
    ChatEmailDigest.update_all(pending_since: nil)
    conversation.messages.create!(user: @alice, content: "Tu es là ?")

    assert_equal 2, digest_jobs.size
    assert_equal 1, chat_notifications_for(@bob).unread.count
  end

  test "une fenêtre restée ouverte trop longtemps (job perdu) est rouverte" do
    conversation = PrivateConversation.between(@alice, @bob)
    conversation.messages.create!(user: @alice, content: "Salut")
    ChatEmailDigest.update_all(pending_since: (ChatEmailDigest::STALE_AFTER + 1.minute).ago)

    conversation.messages.create!(user: @alice, content: "Relance")

    assert_equal 2, digest_jobs.size
  end

  test "la notification est créée même si le destinataire a désactivé les mails" do
    @bob.profil.update!(chat_email_notifications: false)
    conversation = PrivateConversation.between(@alice, @bob)

    conversation.messages.create!(user: @alice, content: "Salut")

    assert_equal 1, chat_notifications_for(@bob).count
  end

  # ── Chat de match ──────────────────────────────────────────────────────────

  test "chat de match : notifie les participants approuvés, pas les demandes en attente" do
    sport = Sport.create!(name: "Foot Notif", slug: "foot-notif", icon: "⚽")
    match = Match.create!(title: "Foot du jeudi", place: "Stade", date: Date.tomorrow, time: 2.hours.from_now,
                          players_needed: 10, level: "Tout niveau", user: @alice, sport: sport)
    pending = create_test_user(email: "notif-pending@example.com")
    match.match_users.create!(user: @alice, role: "organisateur", status: "approved")
    match.match_users.create!(user: @bob, role: "joueur", status: "approved")
    match.match_users.create!(user: pending, role: "joueur", status: "pending")

    match.messages.create!(user: @bob, content: "On se retrouve à 19h ?")

    assert_equal 1, chat_notifications_for(@alice).count
    assert_equal 0, chat_notifications_for(pending).count, "Un joueur en attente n'a pas accès au chat"
    notification = chat_notifications_for(@alice).first
    assert_equal "Nouveau message de Bob Durand · Foot du jeudi", notification.message
    assert_equal "/matches/#{match.slug}?open_chat=1", notification.link
  end

  # ── Chat d'équipe ──────────────────────────────────────────────────────────

  test "chat d'équipe : notifie tous les membres sauf l'expéditeur" do
    team = Team.create!(name: "Les Notifiés", captain: @alice) # capitaine ajouté comme membre
    TeamMember.create!(team: team, user: @bob, role: "member")

    team.messages.create!(user: @alice, content: "Entraînement demain")

    assert_equal 1, chat_notifications_for(@bob).count
    assert_equal 0, chat_notifications_for(@alice).count
    assert_equal "/equipes/#{team.slug}?open_chat=1", chat_notifications_for(@bob).first.link
  end

  # ── Chat de match de tournoi ───────────────────────────────────────────────

  test "chat de match de tournoi : notifie l'adversaire et les organisateurs, pas les autres inscrits" do
    admin = create_test_user(email: "notif-admin@example.com")
    sport = Sport.create!(name: "Padel Notif", slug: "padel-notif", icon: "🎾")
    tournament = Tournament.create!(name: "Open de padel", sport: sport, user: admin, format: "ronde_suisse",
                                    status: "in_progress", max_players: 8, date: Date.tomorrow, place: "Club")
    round = tournament.tournament_rounds.create!(phase: "swiss", number: 1)
    enroll = lambda do |user, co_organizer: false|
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved", co_organizer: co_organizer)
    end
    player_a = enroll.call(@alice)
    player_b = enroll.call(@bob)
    co_org   = create_test_user(email: "notif-coorg@example.com")
    enroll.call(co_org, co_organizer: true)
    other = create_test_user(email: "notif-other@example.com")
    enroll.call(other)
    tmatch = round.tournament_matches.create!(player_a: player_a, player_b: player_b, position: 0)

    tmatch.messages.create!(user: @alice, content: "Samedi 10h ?")

    [@bob, admin, co_org].each do |user|
      assert_equal 1, chat_notifications_for(user).count, "#{user.email} doit être notifié"
    end
    assert_equal 0, chat_notifications_for(other).count, "Un joueur d'un autre match n'a pas accès à ce chat"
    assert_equal "/tournois/#{tournament.to_param}?tmatch_chat=#{tmatch.id}",
                 chat_notifications_for(@bob).first.link
  end
end
