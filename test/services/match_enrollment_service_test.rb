require "test_helper"

# Tests unitaires de MatchEnrollmentService : la logique métier d'inscription
# extraite de MatchUsersController#create. Couvre tous les cas de retour.
class MatchEnrollmentServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @organizer = create_test_user(email: "orga-mes@test.fr", first_name: "Orga", last_name: "T")
    @player    = create_test_user(email: "player-mes@test.fr", first_name: "Joueur", last_name: "T")
    @sport     = Sport.create!(name: "Foot MES", slug: "foot-mes-#{SecureRandom.hex(3)}", icon: "⚽")
  end

  teardown { teardown_db }

  # Fabrique un match avec son organisateur inscrit.
  def build_match(validation_mode: "automatic", players_needed: 4, genre_restriction: "tous")
    match = Match.create!(
      title: "M-#{SecureRandom.hex(3)}", date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      players_needed: players_needed, level: "Débutant", visibility: "public",
      validation_mode: validation_mode, genre_restriction: genre_restriction,
      user: @organizer, sport: @sport
    )
    match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")
    match
  end

  def enroll(match, user, message: nil)
    MatchEnrollmentService.new(match: match, user: user, message: message).call
  end

  # ── Mode automatique, place disponible → approved ──────────────────────────
  test "mode automatique avec place → approved et inscription créée" do
    match = build_match
    result = enroll(match, @player)

    assert_equal :approved, result.status
    assert_equal "approved", match.match_users.find_by(user: @player).status
  end

  # ── Mode manuel → pending ──────────────────────────────────────────────────
  test "mode manuel → pending" do
    match = build_match(validation_mode: "manual")
    result = enroll(match, @player)

    assert_equal :pending, result.status
    assert_equal "pending", match.match_users.find_by(user: @player).status
  end

  # ── Match complet → waiting ────────────────────────────────────────────────
  test "match complet → waiting" do
    match = build_match(players_needed: 1) # place unique
    match.match_users.create!(user: create_test_user(email: "occ@test.fr"), role: "joueur", status: "approved")

    result = enroll(match, @player)
    assert_equal :waiting, result.status
    assert_equal "waiting", match.match_users.find_by(user: @player).status
  end

  # ── Déjà inscrit → refus, aucune création ──────────────────────────────────
  test "déjà inscrit → already_registered sans nouvelle inscription" do
    match = build_match
    match.match_users.create!(user: @player, role: "joueur", status: "approved")

    assert_no_difference "MatchUser.count" do
      assert_equal :already_registered, enroll(match, @player).status
    end
  end

  # ── Restriction de genre : un non-femme est refusé ─────────────────────────
  test "match féminin + user non-femme → gender_restricted sans inscription" do
    match = build_match(genre_restriction: "feminin")

    assert_no_difference "MatchUser.count" do
      assert_equal :gender_restricted, enroll(match, @player).status
    end
  end

  # ── Restriction de genre : une femme est acceptée ──────────────────────────
  test "match féminin + user femme → approved" do
    @player.update_column(:genre, "femme")
    match = build_match(genre_restriction: "feminin")

    assert_equal :approved, enroll(match, @player).status
  end

  # ── L'organisateur reçoit une notification in-app + un email ───────────────
  test "l'inscription notifie l'organisateur (in-app + email)" do
    match = build_match
    assert_difference -> { Notification.where(user: @organizer).count }, 1 do
      assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
        enroll(match, @player)
      end
    end
  end

  # ── Le message optionnel du joueur est bien persisté ───────────────────────
  test "le message du joueur est enregistré sur l'inscription" do
    match = build_match(validation_mode: "manual")
    enroll(match, @player, message: "Salut, je peux jouer gardien")

    assert_equal "Salut, je peux jouer gardien", match.match_users.find_by(user: @player).message
  end
end
