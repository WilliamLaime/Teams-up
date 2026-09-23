require "test_helper"

# Tests de ChatEmailDigestJob — le mail envoyé à la fin de la fenêtre de 3 min.
#
# Règles :
#   - un seul mail regroupe tous les messages non lus de la fenêtre ;
#   - aucun mail si le destinataire a tout lu dans l'app (et la notification de
#     la cloche passe alors à « lue ») ;
#   - aucun mail si le destinataire a perdu l'accès au chat ou désactivé l'option ;
#   - la fenêtre se referme : le message suivant en rouvre une nouvelle.
class ChatEmailDigestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  teardown { teardown_db }

  setup do
    @alice = create_test_user(email: "digest-alice@example.com", first_name: "Alice", last_name: "Martin")
    @bob   = create_test_user(email: "digest-bob@example.com", first_name: "Bob", last_name: "Durand")
    @conversation = PrivateConversation.between(@alice, @bob)
  end

  def send_messages(*contents)
    contents.each { |content| @conversation.messages.create!(user: @alice, content: content) }
  end

  def digest_for(user)
    ChatEmailDigest.find_by!(user: user, chattable: @conversation)
  end

  test "un seul mail regroupe les 3 lignes envoyées d'affilée" do
    send_messages("Salut", "tu joues samedi", "?")

    assert_emails 1 do
      ChatEmailDigestJob.perform_now(digest_for(@bob).id)
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [@bob.email], mail.to
    body = mail.text_part.body.to_s
    %w[Salut tu\ joues\ samedi].each { |line| assert_includes body, line }
  end

  test "aucun mail si le destinataire a lu la conversation entre-temps" do
    send_messages("Salut")
    @conversation.mark_read_for!(@bob)

    assert_no_emails do
      ChatEmailDigestJob.perform_now(digest_for(@bob).id)
    end
    assert Notification.where(user: @bob, notif_type: ChatMessageNotifier::NOTIF_TYPE).all?(&:read?),
           "La notification d'un message déjà lu ne doit plus être signalée comme non lue"
  end

  test "aucun mail si le destinataire a désactivé l'option" do
    @bob.profil.update!(chat_email_notifications: false)
    send_messages("Salut")

    assert_no_emails do
      ChatEmailDigestJob.perform_now(digest_for(@bob).id)
    end
  end

  test "aucun mail si le destinataire n'a plus accès au chat" do
    sport = Sport.create!(name: "Foot Digest", slug: "foot-digest", icon: "⚽")
    match = Match.create!(title: "Foot", place: "Stade", date: Date.tomorrow, time: 2.hours.from_now,
                          players_needed: 10, level: "Tout niveau", user: @alice, sport: sport)
    match.match_users.create!(user: @alice, role: "organisateur", status: "approved")
    bob_mu = match.match_users.create!(user: @bob, role: "joueur", status: "approved")
    match.messages.create!(user: @alice, content: "Rendez-vous 19h")
    bob_mu.destroy! # Bob quitte le match avant la fin de la fenêtre

    assert_no_emails do
      ChatEmailDigestJob.perform_now(ChatEmailDigest.find_by!(user: @bob, chattable: match).id)
    end
  end

  # Un organisateur qui n'a pas écrit dans le chat de la confrontation n'en est
  # pas destinataire : même une ligne de digest créée pour lui (ex. il était
  # destinataire avant le changement de règle) ne doit pas produire de mail.
  test "aucun mail pour un organisateur de tournoi resté silencieux dans le chat" do
    admin = create_test_user(email: "digest-admin@example.com")
    sport = Sport.create!(name: "Ping Digest", slug: "ping-digest", icon: "🏓")
    tournament = Tournament.create!(name: "Open ping", sport: sport, user: admin, format: "ronde_suisse",
                                    status: "in_progress", max_players: 8, date: Date.tomorrow, place: "Club")
    round = tournament.tournament_rounds.create!(phase: "swiss", number: 1)
    player_a = tournament.tournament_users.create!(user: @alice, role: "joueur", status: "approved")
    player_b = tournament.tournament_users.create!(user: @bob, role: "joueur", status: "approved")
    tmatch = round.tournament_matches.create!(player_a: player_a, player_b: player_b, position: 0)
    tmatch.messages.create!(user: @alice, content: "Samedi 10h ?")
    digest = ChatEmailDigest.create!(user: admin, chattable: tmatch, pending_since: Time.current)

    assert_no_emails do
      ChatEmailDigestJob.perform_now(digest.id)
    end
  end

  test "la fenêtre se referme et le message suivant en rouvre une" do
    send_messages("Salut")
    digest = digest_for(@bob)
    ChatEmailDigestJob.perform_now(digest.id)

    digest.reload
    assert_nil digest.pending_since
    assert_not_nil digest.last_sent_at

    clear_enqueued_jobs
    travel 1.second do
      send_messages("Deuxième salve")
    end
    assert_enqueued_with(job: ChatEmailDigestJob, args: [digest.id])
  end

  test "un message déjà envoyé n'est pas renvoyé dans le mail suivant" do
    send_messages("Premier")
    digest = digest_for(@bob)
    ChatEmailDigestJob.perform_now(digest.id)

    travel 1.second do
      send_messages("Second")
      ChatEmailDigestJob.perform_now(digest.id)
    end

    body = ActionMailer::Base.deliveries.last.text_part.body.to_s
    assert_includes body, "Second"
    assert_not_includes body, "Premier"
  end

  test "une conversation supprimée entre-temps ne fait pas échouer le job" do
    send_messages("Salut")
    digest_id = digest_for(@bob).id
    ChatEmailDigest.where(id: digest_id).update_all(chattable_id: 0)

    assert_no_emails do
      ChatEmailDigestJob.perform_now(digest_id)
    end
    assert_not ChatEmailDigest.exists?(digest_id)
  end
end
