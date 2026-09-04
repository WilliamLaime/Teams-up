require "test_helper"

# Tests d'intégration du chat d'organisation d'un match de tournoi.
#
# Ce fil est PRIVÉ à la confrontation : c'est ce qui le rend utilisable pour
# convenir d'un créneau. Il ne se liste nulle part et ne se trouve qu'en cliquant
# la bulle de sa propre carte — la seule barrière est donc l'autorisation, d'où
# l'insistance de ces tests sur les cas de refus.
#
# Règles :
#   - Les deux joueurs, l'admin et les co-organisateurs → 200 OK
#   - Un tiers (même inscrit au tournoi) → redirigé par Pundit
#   - Un visiteur non connecté → redirigé
#   - Une carte supprimée entre-temps → message dans le frame, pas un crash
class TournamentMatchConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @admin = create_test_user(email: "tmc-admin@example.com")
    @sport = Sport.create!(name: "Padel TMC", slug: "padel-tmc", icon: "🎾")
    @tournament = Tournament.create!(name: "T chat", sport: @sport, user: @admin,
                                     format: "ronde_suisse", status: "in_progress", max_players: 8,
                                     date: Date.tomorrow, place: "Terrain test")
    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1)

    @player_a = enroll("pa")
    @player_b = enroll("pb")
    @other    = enroll("autre")            # inscrit au tournoi, mais pas à CE match
    @co_org   = enroll("co", co_organizer: true)
    @stranger = create_test_user(email: "tmc-stranger@example.com")

    @tmatch = @round.tournament_matches.create!(player_a: @player_a, player_b: @player_b, position: 0)
  end

  def enroll(tag, co_organizer: false)
    user = create_test_user(email: "tmc-#{tag}@example.com")
    @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved",
                                        co_organizer: co_organizer)
  end

  # ── GET /tournament_matches/:id/conversation ────────────────────────────────

  test "les deux joueurs du match accèdent au fil" do
    [@player_a, @player_b].each do |player|
      sign_in player.user
      get tournament_match_conversation_path(@tmatch)
      assert_response :success, "Un joueur du match doit voir le fil"
      sign_out player.user
    end
  end

  test "l'admin et le co-organisateur accèdent au fil" do
    [@admin, @co_org.user].each do |user|
      sign_in user
      get tournament_match_conversation_path(@tmatch)
      assert_response :success, "Un organisateur doit pouvoir arbitrer un désaccord sur la date"
      sign_out user
    end
  end

  # Le cas qui compte : être inscrit au tournoi ne donne PAS accès aux fils des
  # autres confrontations.
  test "un joueur d'un autre match est refusé" do
    sign_in @other.user
    get tournament_match_conversation_path(@tmatch)
    assert_response :redirect
    assert_equal "Vous n'êtes pas autorisé à effectuer cette action.", flash[:alert]
  end

  test "un tiers au tournoi est refusé" do
    sign_in @stranger
    get tournament_match_conversation_path(@tmatch)
    assert_response :redirect
  end

  test "un visiteur non connecté est redirigé" do
    get tournament_match_conversation_path(@tmatch)
    assert_response :redirect
  end

  # Un tour régénéré pendant qu'un joueur a la modale ouverte : on répond dans le
  # frame plutôt qu'en 404 pleine page.
  test "une carte disparue rend un message dans le frame" do
    sign_in @player_a.user
    get tournament_match_conversation_path(tournament_match_id: 999_999)
    assert_response :success
    assert_match "existe plus", response.body
  end

  # ── Pastille non-lu ─────────────────────────────────────────────────────────

  test "ouvrir le fil marque les messages comme lus" do
    Message.create!(user: @player_b.user, tournament_match: @tmatch, content: "Jeudi 17h45 ?")

    sign_in @player_a.user
    assert_difference("TournamentMatchChatRead.count", 1) do
      get tournament_match_conversation_path(@tmatch)
    end

    read = TournamentMatchChatRead.find_by(tournament_match: @tmatch, user: @player_a.user)
    assert read.last_read_at.present?
  end

  # Deux onglets ouverts sur le même match : l'upsert doit rester sûr plutôt que
  # de violer l'index unique (tournament_match_id, user_id).
  test "réouvrir le fil ne crée pas de doublon d'accusé de lecture" do
    sign_in @player_a.user
    get tournament_match_conversation_path(@tmatch)

    assert_no_difference("TournamentMatchChatRead.count") do
      get tournament_match_conversation_path(@tmatch)
    end
  end

  # ── POST /tournament_matches/:id/messages ───────────────────────────────────

  test "un joueur du match peut écrire" do
    sign_in @player_a.user
    assert_difference("Message.count", 1) do
      post tournament_match_messages_path(@tmatch),
           params: { message: { content: "Jeudi 17h45 ça te va ?" } },
           as: :turbo_stream
    end
    assert_equal @tmatch.id, Message.last.tournament_match_id
  end

  test "un tiers ne peut pas écrire" do
    sign_in @stranger
    assert_no_difference("Message.count") do
      post tournament_match_messages_path(@tmatch),
           params: { message: { content: "Coucou" } },
           as: :turbo_stream
    end
    assert_response :redirect
  end
end
