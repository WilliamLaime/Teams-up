# Tests du slash command /match (PR 7) :
#   - /match non lié → message éphémère invitant à lier son compte, aucun appel API ;
#   - /match lié → ouverture de la modale via views.open (trigger_id) ;
#   - soumission de la modale (view_submission) : création du match si valide,
#     erreurs inline si invalide, rien si le compte n'est pas lié.
require "test_helper"
require "webmock/minitest"

class SlackCommandsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SIGNING_SECRET = "test_signing_secret"
  VIEWS_OPEN     = "https://slack.com/api/views.open"
  RESPONSE_URL   = "https://hooks.slack.com/commands/T_TEST/123/abc"

  setup do
    @previous_secret = ENV["SLACK_SIGNING_SECRET"]
    ENV["SLACK_SIGNING_SECRET"] = SIGNING_SECRET

    @creator = create_test_user(email: "creator-sc@test.fr", first_name: "Cra", last_name: "T")
    @sport   = Sport.create!(name: "Foot SC", slug: "foot-sc-#{SecureRandom.hex(3)}", icon: "⚽")
    @workspace = SlackWorkspace.create!(team_id: "T_TEST", team_name: "Acme", bot_token: "xoxb-test")
  end

  teardown do
    ENV["SLACK_SIGNING_SECRET"] = @previous_secret
    SlackIdentity.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  def link_creator!
    SlackIdentity.create!(user: @creator, slack_workspace: @workspace,
                          slack_user_id: "U_CREATOR", slack_team_id: "T_TEST")
  end

  # POST signé (form-urlencoded) sur un endpoint Slack. `body` est la chaîne brute.
  def signed_post(path, body, timestamp: Time.now.to_i)
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", SIGNING_SECRET, "v0:#{timestamp}:#{body}")
    post path, params: body,
         headers: {
           "CONTENT_TYPE"              => "application/x-www-form-urlencoded",
           "X-Slack-Request-Timestamp" => timestamp.to_s,
           "X-Slack-Signature"         => signature
         }
  end

  # Corps d'un slash command tel que Slack l'envoie.
  def command_body(command: "/match", user_id: "U_CREATOR")
    URI.encode_www_form(
      command: command, team_id: "T_TEST", user_id: user_id,
      channel_id: "C_GENERAL", trigger_id: "trigger.123", response_url: RESPONSE_URL
    )
  end

  # Corps d'un view_submission (payload=JSON) pour la modale de création.
  def submission_body(values_override: {})
    values = {
      "sport"          => { "value" => { "type" => "static_select", "selected_option" => { "value" => @sport.id.to_s } } },
      "title"          => { "value" => { "type" => "plain_text_input", "value" => "Match depuis Slack" } },
      "date"           => { "value" => { "type" => "datepicker", "selected_date" => Date.tomorrow.iso8601 } },
      "time"           => { "value" => { "type" => "timepicker", "selected_time" => "18:00" } },
      "players_needed" => { "value" => { "type" => "number_input", "value" => "5" } },
      "level"          => { "value" => { "type" => "static_select", "selected_option" => { "value" => "Tout niveau" } } },
      "place"          => { "value" => { "type" => "plain_text_input", "value" => "Parc des sports" } }
    }.merge(values_override)

    payload = {
      "type" => "view_submission",
      "team" => { "id" => "T_TEST" },
      "user" => { "id" => "U_CREATOR" },
      "view" => {
        "callback_id" => Slack::MatchModalBuilder::CALLBACK_ID,
        "private_metadata" => { "channel_id" => "C_GENERAL", "response_url" => RESPONSE_URL, "team_id" => "T_TEST" }.to_json,
        "state" => { "values" => values }
      }
    }
    "payload=#{CGI.escape(payload.to_json)}"
  end

  # ── Slash command ─────────────────────────────────────────────────────────────
  test "/match sans compte lié → éphémère invitant à lier, aucun views.open" do
    signed_post slack_commands_path, command_body
    assert_response :ok
    body = JSON.parse(@response.body)
    assert_equal "ephemeral", body["response_type"]
    assert_includes body["text"], "lie"
    assert_not_requested :post, VIEWS_OPEN
  end

  test "/match avec compte lié → ouvre la modale via views.open" do
    link_creator!
    stub_request(:post, VIEWS_OPEN).to_return(
      status: 200, body: { ok: true }.to_json, headers: { "Content-Type" => "application/json" }
    )

    signed_post slack_commands_path, command_body
    assert_response :ok
    assert_requested(:post, VIEWS_OPEN) do |req|
      json = JSON.parse(req.body)
      json["trigger_id"] == "trigger.123" &&
        json.dig("view", "callback_id") == Slack::MatchModalBuilder::CALLBACK_ID
    end
  end

  test "commande inconnue → éphémère sans views.open" do
    link_creator!
    signed_post slack_commands_path, command_body(command: "/autre")
    assert_response :ok
    assert_includes JSON.parse(@response.body)["text"], "inconnue"
    assert_not_requested :post, VIEWS_OPEN
  end

  # ── Slash command /match-cancel ────────────────────────────────────────────
  test "/match-cancel sans compte lié → éphémère invitant à lier" do
    signed_post slack_commands_path, command_body(command: "/match-cancel")
    assert_response :ok
    body = JSON.parse(@response.body)
    assert_equal "ephemeral", body["response_type"]
    assert_includes body["text"], "lie"
  end

  test "/match-cancel lié avec un match à venir → liste éphémère + bouton match_cancel" do
    link_creator!
    match = Match.create!(
      title: "À annuler", date: Date.tomorrow, time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @creator, sport: @sport
    )

    signed_post slack_commands_path, command_body(command: "/match-cancel")
    assert_response :ok
    body = JSON.parse(@response.body)
    assert_equal "ephemeral", body["response_type"]
    action_ids = body["blocks"].filter_map { |b| b.dig("accessory", "action_id") }
    values     = body["blocks"].filter_map { |b| b.dig("accessory", "value") }
    assert_includes action_ids, "match_cancel"
    assert_includes values, match.id.to_s
  end

  test "/match-cancel lié sans match à venir → éphémère 'aucun match'" do
    link_creator!
    signed_post slack_commands_path, command_body(command: "/match-cancel")
    assert_response :ok
    body = JSON.parse(@response.body)
    assert_includes body["blocks"].to_s, "aucun match"
  end

  test "signature invalide sur /match → 401" do
    post slack_commands_path, params: command_body,
         headers: {
           "CONTENT_TYPE"              => "application/x-www-form-urlencoded",
           "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
           "X-Slack-Signature"         => "v0=deadbeef"
         }
    assert_response :unauthorized
  end

  # ── view_submission ─────────────────────────────────────────────────────────
  test "soumission valide → crée le match et enqueue SlackNotifyJob" do
    link_creator!

    assert_difference "Match.count", 1 do
      assert_enqueued_with(job: SlackNotifyJob) do
        signed_post slack_interactivity_path, submission_body
      end
    end
    assert_response :ok

    match = Match.order(:created_at).last
    assert_equal "Match depuis Slack", match.title
    assert_equal @creator, match.user
    assert_equal "public", match.visibility
    assert_equal "automatic", match.validation_mode
    # Le créateur est bien organisateur approuvé.
    assert match.match_users.exists?(user: @creator, role: "organisateur", status: "approved")
  end

  test "soumission invalide (joueurs manquants) → erreurs inline, aucun match" do
    link_creator!
    empty_players = { "players_needed" => { "value" => { "type" => "number_input", "value" => "" } } }

    assert_no_difference "Match.count" do
      signed_post slack_interactivity_path, submission_body(values_override: empty_players)
    end
    assert_response :ok
    body = JSON.parse(@response.body)
    assert_equal "errors", body["response_action"]
    assert body["errors"].key?(Slack::MatchModalBuilder::BLOCK_PLAYERS)
  end

  test "soumission sans compte lié → aucun match créé" do
    assert_no_difference "Match.count" do
      signed_post slack_interactivity_path, submission_body
    end
    assert_response :ok
  end
end
