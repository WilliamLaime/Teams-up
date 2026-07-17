# Tests de MatchCancellationService : annulation = suppression, avec emails aux
# participants + organisateur et édition des cartes Slack en « Annulé ».
require "test_helper"

class MatchCancellationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @organizer = create_test_user(email: "orga-mcs@test.fr", first_name: "Orga", last_name: "T")
    @player    = create_test_user(email: "player-mcs@test.fr", first_name: "Joueur", last_name: "T")
    @sport     = Sport.create!(name: "Foot MCS", slug: "foot-mcs-#{SecureRandom.hex(3)}", icon: "⚽")
  end

  teardown do
    SlackMatchMessage.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  def build_match
    match = Match.create!(
      title: "M-#{SecureRandom.hex(3)}", date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @organizer, sport: @sport
    )
    match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")
    match.match_users.create!(user: @player, role: "joueur", status: "approved")
    match
  end

  # ── Annulation → match supprimé ────────────────────────────────────────────
  test "annulation supprime le match" do
    match = build_match

    assert_difference "Match.count", -1 do
      result = MatchCancellationService.new(match: match).call
      assert_equal :cancelled, result.status
    end
  end

  # ── Emails d'annulation à chaque destinataire (participant + organisateur) ──
  test "annulation enfile un email par destinataire" do
    match = build_match

    assert_enqueued_jobs 2, only: MatchCancelledMailerJob do
      MatchCancellationService.new(match: match).call
    end
  end

  # ── Carte Slack suivie → job d'édition « Annulé » enfilé ───────────────────
  test "annulation enfile l'édition des cartes Slack quand il y en a" do
    match     = build_match
    workspace = SlackWorkspace.create!(team_id: "T_MCS", team_name: "Acme", bot_token: "xoxb-test")
    SlackMatchMessage.create!(match: match, slack_workspace: workspace,
                              channel_id: "C_MCS", message_ts: "1.2")

    assert_enqueued_with(job: SlackMatchCancelJob) do
      MatchCancellationService.new(match: match).call
    end
  end

  # ── Aucune carte Slack → pas de job d'édition ──────────────────────────────
  test "annulation sans carte Slack n'enfile pas SlackMatchCancelJob" do
    match = build_match

    assert_no_enqueued_jobs only: SlackMatchCancelJob do
      MatchCancellationService.new(match: match).call
    end
  end
end
