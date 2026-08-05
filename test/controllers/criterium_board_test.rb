require "test_helper"

# ── Rendu du board d'un Critérium Fédéral ─────────────────────────────────────
# CriteriumFlow est testé unitairement (test/services/criterium_flow_test.rb) ;
# ici on vérifie que la page se rend RÉELLEMENT à chaque étape du format. Sans ce
# filet, une phase nouvelle (barrages) pourrait n'être affichée nulle part, ou un
# libellé de tour lever une exception, sans qu'aucun test ne le voie.
class CriteriumBoardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = create_test_user(email: "owner-crit@example.com", first_name: "Alice", last_name: "Test")
    @sport = Sport.create!(name: "Ping board", slug: "ping-pong", icon: "🏓")
    @tournament = Tournament.create!(name: "Critérium test", sport: @sport, user: @owner,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "cb#{i}@example.com")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
  end

  teardown { teardown_db }

  def resolve_all_pending!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  def play_until_barrages!
    TournamentEngine.for(@tournament).next_round!
    20.times do
      break if @tournament.barrage_rounds.exists?

      resolve_all_pending!
      TournamentEngine.for(@tournament).next_round!
    end
  end

  test "le board se rend pendant la phase de poules" do
    TournamentEngine.for(@tournament).next_round!

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "[data-phase=?]", "main"
    assert_select "[data-phase=?]", "barrage", count: 0, message: "pas de barrages avant la fin des poules"
  end

  test "le board affiche une section et une pastille Barrages une fois les poules terminées" do
    play_until_barrages!
    assert @tournament.barrage_rounds.exists?, "les barrages doivent exister pour ce test"

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "section[data-phase=?] .tournament-phase__title", "barrage", text: "Barrages"
    assert_select ".phase-nav__pill[data-phase=?]", "barrage"
    # La phase affichée par défaut doit être la plus avancée.
    assert_select "[data-tournament-phase-switch-default-value=?]", "barrage"
  end

  test "le board se rend une fois le tableau final démarré, et bascule dessus par défaut" do
    play_until_barrages!
    resolve_all_pending!
    TournamentEngine.for(@tournament).next_round!
    assert @tournament.reload.bracket_started?

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "[data-tournament-phase-switch-default-value=?]", "bracket"
    # Les trois pastilles coexistent : poules, barrages, tableau final.
    assert_select ".phase-nav__pill", 3
  end

  test "l'onglet Classement se rend avec le barème points-parties du règlement" do
    play_until_barrages!

    sign_in @owner
    get tournament_path(@tournament, tab: "ranking")

    assert_response :success
  end

  test "le résumé de structure d'un Critérium mentionne barrages et consolante" do
    assert_match(/poules de 4/, @tournament.structure_summary)
    assert_match(/barrages/, @tournament.structure_summary)
    assert_match(/consolante/, @tournament.structure_summary)
  end
end
