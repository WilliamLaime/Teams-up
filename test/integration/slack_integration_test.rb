# Tests d'intégration pour l'intégration Slack (PR 1 → 3).
# Couvre : rendu de la page Intégrations, du formulaire de création avec/sans compte
# Slack lié, le lister de destinations groupées, et l'envoi via SlackNotifyJob.
require "test_helper"
require "webmock/minitest"

class SlackIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

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
    SlackFavoriteDestination.delete_all
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
    # Le formulaire ne porte plus que le turbo-frame : le champ lui-même est chargé
    # à part pour ne pas faire attendre la page sur l'API Slack.
    get new_match_path
    assert_response :success
    assert_select "turbo-frame#slack_share_field[src]", count: 1

    get slack_share_field_path
    assert_response :success
    assert_select "input#post_to_slack", count: 1
    # Workspace unique → champ caché (pas de select workspace)
    assert_select "input[type=hidden][name=slack_workspace_id]", count: 1
    # Destination = combobox recherchable : champ caché slack_channel_id + input combobox
    assert_select "input[type=hidden][name=slack_channel_id]", count: 1
    assert_select "input[role=combobox][data-slack-destination-target=input]", count: 1
    # Le JSON embarqué contient le channel et le membre pour le peuplement client-side
    data = css_select("[data-slack-destination-workspaces-value]").first["data-slack-destination-workspaces-value"]
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

  # ── Pagination : Slack tronque ses listes et fournit un curseur ───────────────
  # Sans suivre next_cursor, un workspace de plus de 200 conversations perdait
  # silencieusement les suivantes (elles ne sont pas triées par nom côté Slack).
  test "ChannelLister suit next_cursor pour lister tous les channels" do
    ws = link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(
        # 1re page : curseur non vide → il reste des channels à lire.
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { ok: true, channels: [{ id: "C1", name: "general" }],
                  response_metadata: { next_cursor: "page2" } }.to_json },
        # 2e page : curseur vide → fin du parcours.
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { ok: true, channels: [{ id: "C2", name: "pingpong-midi" }],
                  response_metadata: { next_cursor: "" } }.to_json }
      )
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, members: [] }.to_json)

    dest = Slack::ChannelLister.destinations(ws)
    assert_equal [["#general", "C1"], ["#pingpong-midi", "C2"]], dest["Channels"]

    # La 2e requête doit bien transmettre le curseur reçu.
    assert_requested :post, "https://slack.com/api/conversations.list",
                     body: hash_including("cursor" => "page2"), times: 1
  end

  # ── Les arguments doivent VRAIMENT partir dans la requête ─────────────────────
  # conversations.list et users.list n'acceptent pas de corps JSON : envoyés ainsi,
  # Slack répond ok: true mais ignore tout (types, limit, cursor) et renvoie la
  # première page des seuls channels publics. Le bug était totalement muet — d'où
  # ce test sur la forme de la requête et pas seulement sur son résultat.
  test "ChannelLister envoie ses arguments en form-urlencoded, pas en JSON" do
    ws = link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, channels: [] }.to_json)
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, members: [] }.to_json)

    Slack::ChannelLister.destinations(ws)

    assert_requested :post, "https://slack.com/api/conversations.list", times: 1 do |req|
      assert_includes req.headers["Content-Type"].to_s, "application/x-www-form-urlencoded"
      params = Rack::Utils.parse_nested_query(req.body)
      # Sans `types`, les channels privés ne sont jamais listés.
      assert_equal "public_channel,private_channel", params["types"]
      assert_equal "200", params["limit"]
      true
    end
  end

  # ── Robustesse : un appel qui échoue ne fait pas disparaître l'autre liste ─────
  test "ChannelLister isole les appels : users.list en échec garde les channels" do
    ws = link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, channels: [{ id: "C1", name: "general" }] }.to_json)
    # Scope manquant sur users.list (erreur NON fatale) → les DM sont perdus, pas les channels.
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: false, error: "missing_scope" }.to_json)

    result = Slack::ChannelLister.resolve(ws)
    assert_equal [["#general", "C1"]], result[:groups]["Channels"]
    assert_nil result[:groups]["Messages directs"]
    assert_not result[:auth_failed] # missing_scope n'exige pas une réinstallation
  end

  # ── Robustesse : token mort → auth_failed pour piloter le bandeau « réinstalle » ─
  test "ChannelLister signale auth_failed quand le token du bot est révoqué" do
    ws = link_slack!
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: false, error: "invalid_auth" }.to_json)
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: false, error: "invalid_auth" }.to_json)

    result = Slack::ChannelLister.resolve(ws)
    assert_empty result[:groups]
    assert result[:auth_failed]
  end

  # ── Favoris : épinglage / désépinglage via l'endpoint fetch ───────────────────
  test "POST /slack/favorites épingle une destination pour l'identité du workspace" do
    ws = link_slack!
    sign_in @user
    assert_difference "SlackFavoriteDestination.count", 1 do
      post slack_favorites_path,
           params: { slack_workspace_id: ws.id, channel_id: "C1", channel_name: "#general" }
    end
    assert_response :success
    fav = SlackFavoriteDestination.last
    assert_equal "C1", fav.channel_id
    assert_equal "#general", fav.channel_name
    assert_equal @user.slack_identities.first.id, fav.slack_identity_id
  end

  test "POST /slack/favorites est idempotent (find_or_initialize)" do
    ws = link_slack!
    sign_in @user
    2.times do
      post slack_favorites_path,
           params: { slack_workspace_id: ws.id, channel_id: "C1", channel_name: "#general" }
    end
    assert_equal 1, SlackFavoriteDestination.where(channel_id: "C1").count
  end

  test "DELETE /slack/favorites désépingle la destination" do
    ws = link_slack!
    identity = @user.slack_identities.first
    identity.slack_favorite_destinations.create!(channel_id: "C1", channel_name: "#general")
    sign_in @user
    assert_difference "SlackFavoriteDestination.count", -1 do
      delete slack_favorites_path, params: { slack_workspace_id: ws.id, channel_id: "C1" }
    end
    assert_response :success
  end

  test "POST /slack/favorites sur un workspace non lié renvoie 404" do
    link_slack!
    sign_in @user
    assert_no_difference "SlackFavoriteDestination.count" do
      post slack_favorites_path,
           params: { slack_workspace_id: 999_999, channel_id: "C1", channel_name: "#x" }
    end
    assert_response :not_found
  end

  test "slack_destinations_for embarque les favoris par workspace" do
    ws = link_slack!
    identity = @user.slack_identities.first
    identity.slack_favorite_destinations.create!(channel_id: "C1", channel_name: "#general")
    stub_request(:post, "https://slack.com/api/conversations.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, channels: [] }.to_json)
    stub_request(:post, "https://slack.com/api/users.list")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { ok: true, members: [] }.to_json)

    sign_in @user
    get slack_share_field_path # champ chargé dans son turbo-frame
    assert_response :success
    # Le JSON embarqué doit contenir la paire favorite.
    assert_match(/#general/, response.body)
  end

  # ── Partage manuel depuis la page match : organisateur lié → job enqueue ───────
  test "POST share_on_slack par l'organisateur lié enqueue SlackNotifyJob avec la destination" do
    ws = link_slack!
    sign_in @user
    assert_enqueued_with(job: SlackNotifyJob,
                         args: ["Match", @match.id, @user.id, "C1", ws.id.to_s]) do
      post share_on_slack_match_path(@match),
           params: { slack_channel_id: "C1", slack_workspace_id: ws.id }
    end
    assert_redirected_to match_path(@match)
  end

  # ── Partage manuel : un non-organisateur est refusé et rien n'est enqueue ───────
  test "POST share_on_slack par un non-organisateur est refusé" do
    link_slack!
    intruder = create_test_user(email: "intruder@example.com", first_name: "Eve", last_name: "Test")
    sign_in intruder
    assert_no_enqueued_jobs(only: SlackNotifyJob) do
      post share_on_slack_match_path(@match), params: { slack_channel_id: "C1" }
    end
    assert_response :redirect # Pundit → redirect_back avec alerte
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
