# Tests d'intégration pour l'intégration Slack (PR 1 → 3).
# Couvre : rendu de la page Intégrations, du formulaire de création avec/sans compte
# Slack lié, le lister de destinations groupées, et l'envoi via SlackNotifyJob.
require "test_helper"
require "webmock/minitest"

class SlackIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user  = create_test_user(email: "owner@example.com", first_name: "Alice", last_name: "Test")
    @sport = Sport.create!(name: "Football Test", slug: "football-test", icon: "⚽")
    @match = Match.create!(
      title: "Match test", date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      players_needed: 4, level: "Débutant", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      user: @user, sport: @sport
    )
    @match.match_users.create!(user: @user, role: "organisateur", status: "approved")
  end

  # Les tables Slack ne sont pas gérées par teardown_db → on les nettoie ici pour
  # éviter des lignes orphelines qui violeraient les FK au chargement des fixtures
  # du test suivant.
  teardown do
    SlackIdentity.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  # Relie @user à un workspace Slack de test.
  def link_slack!
    ws = SlackWorkspace.create!(team_id: "T_TEST", team_name: "Acme", bot_token: "xoxb-test")
    SlackIdentity.create!(user: @user, slack_workspace: ws, slack_user_id: "U_TEST",
                          slack_team_id: "T_TEST", preferred_channel_id: "C_GEN")
    ws
  end

  # ── Page Intégrations ───────────────────────────────────────────────────────
  test "GET /profil/integrations rend 200 avec le bouton de connexion Slack" do
    sign_in @user
    get profil_integrations_path
    assert_response :success
    assert_select "a", text: /Se connecter avec Slack/
  end

  # ── Formulaire de création : compte NON lié → pas de champ Slack, aucun appel API ──
  test "GET /matches/new sans Slack lié ne montre pas le partage Slack" do
    sign_in @user
    get new_match_path
    assert_response :success
    assert_select "input#post_to_slack", count: 0
  end

  # ── Formulaire de création : compte lié → champ Slack + destinations embarquées ──
  # Les destinations sont peuplées côté client (Stimulus) depuis l'attribut data JSON ;
  # on vérifie donc la présence de la case, du champ workspace, et que le JSON embarqué
  # contient bien le channel et le membre (DM).
  test "GET /matches/new avec Slack lié montre le partage et embarque les destinations" do
    link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, channels: [{ id: "C1", name: "general" }] }.to_json)
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, members: [
                   { id: "U9", name: "bob", deleted: false, is_bot: false, profile: { real_name: "Bob Martin" } }
                 ] }.to_json)

    sign_in @user
    get new_match_path
    assert_response :success
    assert_select "input#post_to_slack", count: 1
    # Workspace unique → champ caché (pas de select workspace)
    assert_select "input[type=hidden][name=slack_workspace_id]", count: 1
    assert_select "select#slack_channel_id", count: 1
    # Le JSON embarqué contient le channel et le membre pour le peuplement client-side
    data = css_select("[data-slack-share-data-value]").first["data-slack-share-data-value"]
    assert_includes data, "C1"
    assert_includes data, "U9"
    assert_includes data, "Messages directs"
  end

  # ── Lister : structure groupée channels + membres ────────────────────────────
  test "ChannelLister renvoie channels et membres groupés" do
    ws = link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, channels: [{ id: "C1", name: "general" }] }.to_json)
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, members: [
                   { id: "U9", name: "bob", deleted: false, is_bot: false, profile: { real_name: "Bob" } },
                   { id: "UBOT", name: "botty", deleted: false, is_bot: true, profile: {} }
                 ] }.to_json)

    dest = Slack::ChannelLister.destinations(ws)
    assert_equal [["#general", "C1"]], dest["Channels"]
    assert_equal [["Bob", "U9"]], dest["Messages directs"] # le bot est exclu
  end

  # ── Envoi : SlackNotifyJob poste avec le bon token et la bonne destination ─────
  test "SlackNotifyJob poste le match dans la destination résolue" do
    link_slack!
    stub_request(:post, "https://slack.com/api/chat.postMessage")
      .with(headers: { "Authorization" => "Bearer xoxb-test" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true }.to_json)

    SlackNotifyJob.perform_now("Match", @match.id, @user.id, "U9") # DM vers un membre

    assert_requested(:post, "https://slack.com/api/chat.postMessage") do |req|
      JSON.parse(req.body)["channel"] == "U9"
    end
  end
end
