require "test_helper"

# Tests unitaires de MatchUnenrollmentService : la logique métier de
# désinscription extraite de MatchUsersController#destroy (et réutilisée par la
# désinscription Slack). Couvre les cas de retour et la promotion de la file.
class MatchUnenrollmentServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @organizer = create_test_user(email: "orga-mus@test.fr", first_name: "Orga", last_name: "T")
    @player    = create_test_user(email: "player-mus@test.fr", first_name: "Joueur", last_name: "T")
    @sport     = Sport.create!(name: "Foot MUS", slug: "foot-mus-#{SecureRandom.hex(3)}", icon: "⚽")
  end

  teardown { teardown_db }

  # Fabrique un match avec son organisateur inscrit.
  def build_match(players_needed: 4)
    match = Match.create!(
      title: "M-#{SecureRandom.hex(3)}", date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      players_needed: players_needed, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @organizer, sport: @sport
    )
    match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")
    match
  end

  def unenroll(match, user)
    MatchUnenrollmentService.new(match: match, user: user).call
  end

  # ── Joueur approuvé qui part → inscription supprimée ───────────────────────
  test "joueur approuvé → left et inscription supprimée" do
    match = build_match
    match.match_users.create!(user: @player, role: "joueur", status: "approved")

    result = nil
    assert_difference "MatchUser.count", -1 do
      result = unenroll(match, @player)
    end

    assert_equal :left, result.status
    assert_equal @player, result.leaving_user
    assert result.was_approved
    assert_nil match.match_users.find_by(user: @player)
  end

  # ── Départ d'un approuvé → email de départ à l'organisateur ────────────────
  test "le départ d'un approuvé envoie un email à l'organisateur" do
    match = build_match
    match.match_users.create!(user: @player, role: "joueur", status: "approved")

    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      unenroll(match, @player)
    end
  end

  # ── Non inscrit → not_registered, aucune suppression ───────────────────────
  test "joueur non inscrit → not_registered sans suppression" do
    match = build_match

    assert_no_difference "MatchUser.count" do
      assert_equal :not_registered, unenroll(match, @player).status
    end
  end

  # ── Départ d'un approuvé → promotion du 1er en file d'attente ──────────────
  test "le départ d'un approuvé promeut le premier en file d'attente" do
    match   = build_match(players_needed: 1) # place unique
    waiting = create_test_user(email: "waiter-mus@test.fr", first_name: "Wai", last_name: "T")
    match.match_users.create!(user: @player, role: "joueur", status: "approved")
    waiting_mu = match.match_users.create!(user: waiting, role: "joueur", status: "waiting")

    unenroll(match, @player)

    assert_equal "approved", waiting_mu.reload.status
  end

  # ── Départ d'un joueur en attente (pending) → pas d'email, pas de promotion ─
  test "le départ d'un pending ne déclenche ni email ni promotion" do
    match = build_match
    match.match_users.create!(user: @player, role: "joueur", status: "pending")

    result = nil
    assert_no_enqueued_jobs only: ActionMailer::MailDeliveryJob do
      result = unenroll(match, @player)
    end

    assert_equal :left, result.status
    assert_not result.was_approved
  end
end
