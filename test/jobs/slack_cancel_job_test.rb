# Tests de SlackCancelJob : annulation depuis Slack, réservée à l'organisateur.
require "test_helper"
require "webmock/minitest"

class SlackCancelJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RESPONSE_URL = "https://hooks.slack.com/actions/T_CANCEL/1/abc"

  setup do
    @organizer = create_test_user(email: "orga-scj@test.fr", first_name: "Orga", last_name: "T")
    @other     = create_test_user(email: "other-scj@test.fr", first_name: "Autre", last_name: "T")
    @sport     = Sport.create!(name: "Foot SCJ", slug: "foot-scj-#{SecureRandom.hex(3)}", icon: "⚽")
    @workspace = SlackWorkspace.create!(team_id: "T_CANCEL", team_name: "Acme", bot_token: "xoxb-test")

    @match = Match.create!(
      title: "SCJ", date: Date.tomorrow, time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @organizer, sport: @sport
    )
    @match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")
  end

  teardown do
    SlackIdentity.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  def link!(user, slack_user_id)
    SlackIdentity.create!(user: user, slack_workspace: @workspace,
                          slack_user_id: slack_user_id, slack_team_id: "T_CANCEL")
  end

  def run_job(slack_user_id:)
    SlackCancelJob.perform_now(
      match_id: @match.id, team_id: "T_CANCEL",
      slack_user_id: slack_user_id, response_url: RESPONSE_URL
    )
  end

  # ── L'organisateur annule → match supprimé ─────────────────────────────────
  test "organisateur → annule le match" do
    link!(@organizer, "U_ORGA")
    stub_request(:post, RESPONSE_URL).to_return(status: 200, body: "ok")

    assert_difference "Match.count", -1 do
      run_job(slack_user_id: "U_ORGA")
    end
  end

  # ── Un non-organisateur ne peut pas annuler ────────────────────────────────
  test "non-organisateur → refus, match conservé" do
    link!(@other, "U_OTHER")
    stub = stub_request(:post, RESPONSE_URL)
             .with(body: /Seul l'organisateur/)
             .to_return(status: 200, body: "ok")

    assert_no_difference "Match.count" do
      run_job(slack_user_id: "U_OTHER")
    end
    assert_requested stub
  end

  # ── Compte Slack non lié → invitation à lier, match conservé ───────────────
  test "compte non lié → invitation à lier son compte" do
    stub_request(:post, RESPONSE_URL).to_return(status: 200, body: "ok")

    assert_no_difference "Match.count" do
      run_job(slack_user_id: "U_UNKNOWN")
    end
  end
end
