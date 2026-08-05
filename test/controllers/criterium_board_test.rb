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
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
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

  # Déroule le tournoi jusqu'à son terme : toutes les branches, jusqu'au dernier
  # match de classement.
  def play_all!
    60.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.reload.completed?

      resolve_all_pending!
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
    # La consolante s'ouvre EN MÊME TEMPS que le tableau final (mêmes sources : les
    # barrages), donc quatre pastilles dès ce moment : poules, barrages, tableau,
    # consolante. Les matchs de classement, eux, naissent des perdants du 1er tour.
    assert_select ".phase-nav__pill[data-phase=?]", "consolation"
    assert_select ".phase-nav__pill", 4
    assert_select "section[data-phase=?] .tournament-phase__title", "consolation"
  end

  test "le board affiche les matchs de classement une fois le tournoi déroulé" do
    play_all!
    assert @tournament.reload.completed?, "le tournoi doit être terminé pour ce test"

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".phase-nav__pill[data-phase=?]", "classification"
    assert_select "section[data-phase=?] .tournament-phase__title", "classification",
                  text: "Matchs de classement"
    # Un bloc par branche, titré par la plage de places qu'il attribue.
    assert_select "section[data-phase='classification'] .tournament-phase__subtitle",
                  text: "Match pour la 3e place"
    assert_select ".phase-nav__pill", 5
  end

  test "l'onglet Classement se rend avec le barème points-parties du règlement" do
    play_until_barrages!

    sign_in @owner
    get tournament_path(@tournament, tab: "ranking")

    assert_response :success
  end

  test "l'onglet Classement affiche les places finales une fois le tournoi terminé" do
    play_all!

    sign_in @owner
    get tournament_path(@tournament, tab: "ranking")

    assert_response :success
    assert_select ".tournament-ranking__pool-title", text: "Classement final"
    # 16 joueurs, 4 poules de 4 → chaque place est jouée, donc aucun badge ex æquo.
    assert_select ".tournament-ranking__tie", count: 0
  end

  test "le résumé de structure d'un Critérium mentionne barrages et consolante" do
    assert_match(/poules de 4/, @tournament.structure_summary)
    assert_match(/barrages/, @tournament.structure_summary)
    assert_match(/consolante/, @tournament.structure_summary)
  end
end
