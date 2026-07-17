# Tests de l'endpoint Events API de Slack (PR 8) :
#   - handshake `url_verification` signé → renvoie le challenge en texte brut ;
#   - event quelconque signé → simple accusé de réception (aucun effet) ;
#   - signature absente/invalide → 401 (garde de Slack::BaseController).
#
# L'Events API poste du JSON (Content-Type application/json) ; la signature HMAC
# porte sur le body brut, indépendamment du content-type.
require "test_helper"

class SlackEventsTest < ActionDispatch::IntegrationTest
  SIGNING_SECRET = "test_signing_secret"

  setup do
    @previous_secret = ENV["SLACK_SIGNING_SECRET"]
    ENV["SLACK_SIGNING_SECRET"] = SIGNING_SECRET
  end

  teardown do
    ENV["SLACK_SIGNING_SECRET"] = @previous_secret
    teardown_db
  end

  # POST JSON signé sur un endpoint Slack. `body` est la chaîne JSON brute.
  def signed_post_json(path, body, timestamp: Time.now.to_i, signature: nil)
    signature ||= "v0=" + OpenSSL::HMAC.hexdigest("SHA256", SIGNING_SECRET, "v0:#{timestamp}:#{body}")
    post path, params: body,
         headers: {
           "CONTENT_TYPE"              => "application/json",
           "X-Slack-Request-Timestamp" => timestamp.to_s,
           "X-Slack-Signature"         => signature
         }
  end

  test "url_verification signé → renvoie le challenge en texte brut" do
    challenge = "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"
    body = { type: "url_verification", token: "tok", challenge: challenge }.to_json

    signed_post_json "/slack/events", body

    assert_response :ok
    assert_equal challenge, @response.body
  end

  test "event quelconque signé → 200 sans effet" do
    body = { type: "event_callback", event: { type: "message", text: "coucou" } }.to_json

    signed_post_json "/slack/events", body

    assert_response :ok
    assert_empty @response.body
  end

  test "signature invalide → 401" do
    body = { type: "url_verification", challenge: "x" }.to_json

    signed_post_json "/slack/events", body, signature: "v0=deadbeef"

    assert_response :unauthorized
  end
end
