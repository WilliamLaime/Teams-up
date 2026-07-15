# Tests de l'inscription depuis Slack (PR 6) :
#   - vérification de signature HMAC de l'endpoint /slack/interactivity ;
#   - enqueue de SlackEnrollJob sur un clic « S'inscrire » valide ;
#   - logique du job (compte non lié → invitation à lier ; compte lié → inscription).
require "test_helper"
require "webmock/minitest"

class SlackInteractivityTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SIGNING_SECRET = "test_signing_secret"
  RESPONSE_URL   = "https://hooks.slack.com/actions/T_TEST/123/abc"

  setup do
    # L'endpoint refuse tout si le secret n'est pas configuré → on en pose un de test.
    @previous_secret = ENV["SLACK_SIGNING_SECRET"]
    ENV["SLACK_SIGNING_SECRET"] = SIGNING_SECRET

    @organizer = create_test_user(email: "orga-si@test.fr", first_name: "Orga", last_name: "T")
    @joiner    = create_test_user(email: "joiner-si@test.fr", first_name: "Joe", last_name: "T")
    @sport     = Sport.create!(name: "Foot SI", slug: "foot-si-#{SecureRandom.hex(3)}", icon: "⚽")
    @match = Match.create!(
      title: "Match SI", date: Date.tomorrow, time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @organizer, sport: @sport
    )
    @match.match_users.create!(user: @organizer, role: "organisateur", status: "approved")

    @workspace = SlackWorkspace.create!(team_id: "T_TEST", team_name: "Acme", bot_token: "xoxb-test")
  end

  teardown do
    ENV["SLACK_SIGNING_SECRET"] = @previous_secret
    SlackIdentity.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  # Relie @joiner au workspace de test.
  def link_joiner!
    SlackIdentity.create!(user: @joiner, slack_workspace: @workspace,
                          slack_user_id: "U_JOINER", slack_team_id: "T_TEST")
  end

  # Payload block_actions "match_join" tel que Slack l'envoie.
  def join_payload(match_id: @match.id, user_id: "U_JOINER", team_id: "T_TEST")
    {
      "type" => "block_actions",
      "team" => { "id" => team_id },
      "user" => { "id" => user_id },
      "response_url" => RESPONSE_URL,
      "actions" => [{ "action_id" => "match_join", "value" => match_id.to_s }]
    }
  end

  # POST signé sur /slack/interactivity (corps form-urlencoded exact + signature v0).
  def signed_post(payload, secret: SIGNING_SECRET, timestamp: Time.now.to_i, signature: nil)
    body = "payload=#{CGI.escape(payload.to_json)}"
    signature ||= "v0=" + OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "v0:#{timestamp}:#{body}")
    post slack_interactivity_path, params: body,
         headers: {
           "CONTENT_TYPE"              => "application/x-www-form-urlencoded",
           "X-Slack-Request-Timestamp" => timestamp.to_s,
           "X-Slack-Signature"         => signature
         }
  end

  # ── Signature ────────────────────────────────────────────────────────────────
  test "signature valide + match_join → 200 et SlackEnrollJob enqueue" do
    assert_enqueued_with(job: SlackEnrollJob) do
      signed_post(join_payload)
    end
    assert_response :ok
  end

  test "signature invalide → 401 et aucun job" do
    assert_no_enqueued_jobs(only: SlackEnrollJob) do
      signed_post(join_payload, signature: "v0=deadbeef")
    end
    assert_response :unauthorized
  end

  test "horodatage expiré (> 5 min) → 401 (anti-replay)" do
    assert_no_enqueued_jobs(only: SlackEnrollJob) do
      signed_post(join_payload, timestamp: 10.minutes.ago.to_i)
    end
    assert_response :unauthorized
  end

  test "sans SLACK_SIGNING_SECRET configuré → 401 (fail-closed)" do
    ENV["SLACK_SIGNING_SECRET"] = nil
    assert_no_enqueued_jobs(only: SlackEnrollJob) do
      # On signe avec un secret quelconque : peu importe, le serveur refuse d'emblée.
      signed_post(join_payload, secret: "whatever")
    end
    assert_response :unauthorized
  end

  test "payload non block_actions → 200 sans job" do
    assert_no_enqueued_jobs(only: SlackEnrollJob) do
      signed_post({ "type" => "shortcut" })
    end
    assert_response :ok
  end

  # ── Job : compte lié → inscription réelle ──────────────────────────────────────
  test "SlackEnrollJob avec compte lié inscrit le joueur et répond en éphémère" do
    link_joiner!
    stub = stub_request(:post, RESPONSE_URL).to_return(status: 200, body: "ok")

    assert_difference -> { @match.match_users.where(user: @joiner).count }, 1 do
      SlackEnrollJob.perform_now(match_id: @match.id, team_id: "T_TEST",
                                 slack_user_id: "U_JOINER", response_url: RESPONSE_URL)
    end
    assert_equal "approved", @match.match_users.find_by(user: @joiner).status
    assert_requested(:post, RESPONSE_URL) { |req| JSON.parse(req.body)["text"].include?("inscrit") }
  end

  # ── Job : compte NON lié → invitation à lier, aucune inscription ───────────────
  test "SlackEnrollJob sans compte lié invite à lier et n'inscrit personne" do
    stub = stub_request(:post, RESPONSE_URL).to_return(status: 200, body: "ok")

    assert_no_difference "MatchUser.count" do
      SlackEnrollJob.perform_now(match_id: @match.id, team_id: "T_TEST",
                                 slack_user_id: "U_INCONNU", response_url: RESPONSE_URL)
    end
    assert_requested(:post, RESPONSE_URL) { |req| JSON.parse(req.body)["text"].include?("lie") }
  end

  # ── Job : match introuvable → message dédié, aucune inscription ────────────────
  test "SlackEnrollJob sur un match supprimé répond sans planter" do
    link_joiner!
    stub = stub_request(:post, RESPONSE_URL).to_return(status: 200, body: "ok")

    assert_no_difference "MatchUser.count" do
      SlackEnrollJob.perform_now(match_id: 0, team_id: "T_TEST",
                                 slack_user_id: "U_JOINER", response_url: RESPONSE_URL)
    end
    assert_requested(:post, RESPONSE_URL) { |req| JSON.parse(req.body)["text"].include?("n'existe plus") }
  end
end
