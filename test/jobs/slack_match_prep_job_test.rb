# Tests de SlackMatchPrepJob : le rappel "préparez-vous" ~15 min avant le match.
# Couvre la garde temporelle (fenêtre de rappel), l'envoi unique par créneau
# (flag slack_prep_sent_at) et le ciblage du bon channel.
#
# On fige l'heure avec travel_to autour de build_datetime plutôt que de bricoler
# les colonnes date/time (dont la lecture dépend du fuseau).
require "test_helper"
require "webmock/minitest"

class SlackMatchPrepJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  POST_URL = "https://slack.com/api/chat.postMessage"

  setup do
    @organizer = create_test_user(email: "orga-prep@test.fr", first_name: "Orga", last_name: "T")
    @sport     = Sport.create!(name: "Foot PREP", slug: "foot-prep-#{SecureRandom.hex(3)}", icon: "⚽")
    @workspace = SlackWorkspace.create!(team_id: "T_PREP", team_name: "Acme", bot_token: "xoxb-test")

    @match = Match.create!(
      title: "Prep", date: Date.tomorrow, time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @organizer, sport: @sport
    )
    @match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")
    SlackMatchMessage.create!(match: @match, slack_workspace: @workspace,
                              channel_id: "C_PREP", message_ts: "111.222")
    @kickoff = @match.build_datetime
  end

  teardown do
    SlackMatchMessage.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  def stub_post
    stub_request(:post, POST_URL).to_return(
      status: 200, body: { ok: true, channel: "C_PREP", ts: "999.888" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  # ── Match imminent (~15 min avant) → un message posté dans le bon channel ──
  test "match imminent → poste le rappel" do
    stub = stub_post
    travel_to(@kickoff - 15.minutes) do
      SlackMatchPrepJob.perform_now(@match.id)
    end

    assert_requested stub, times: 1
    assert_not_nil @match.reload.slack_prep_sent_at
  end

  # ── Match trop lointain (hors fenêtre) → aucun envoi ───────────────────────
  test "match hors fenêtre → n'envoie rien" do
    stub = stub_post
    travel_to(@kickoff - 2.hours) do
      SlackMatchPrepJob.perform_now(@match.id)
    end

    assert_not_requested stub
    assert_nil @match.reload.slack_prep_sent_at
  end

  # ── Match déjà commencé → aucun envoi ──────────────────────────────────────
  test "match déjà commencé → n'envoie rien" do
    stub = stub_post
    travel_to(@kickoff + 5.minutes) do
      SlackMatchPrepJob.perform_now(@match.id)
    end

    assert_not_requested stub
  end

  # ── Deux jobs empilés sur le même créneau → un seul envoi ──────────────────
  test "double exécution → un seul rappel (flag)" do
    stub = stub_post
    travel_to(@kickoff - 15.minutes) do
      SlackMatchPrepJob.perform_now(@match.id)
      SlackMatchPrepJob.perform_now(@match.id)
    end

    assert_requested stub, times: 1
  end

  # ── Aucune carte Slack suivie → aucun envoi ────────────────────────────────
  test "match sans carte Slack → n'envoie rien" do
    @match.slack_match_messages.delete_all
    stub = stub_post
    travel_to(@kickoff - 15.minutes) do
      SlackMatchPrepJob.perform_now(@match.id)
    end

    assert_not_requested stub
  end
end
