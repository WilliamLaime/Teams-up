require "test_helper"

# ── Endpoint de constitution des poules (Lot 7) ───────────────────────────────
# Le panneau confie à l'organisateur deux réglages de structure et le chapeau de
# chaque inscrit. Trois choses doivent tenir :
#   • seule l'organisation y accède, et seulement avant le lancement ;
#   • un `pot` ne peut pas servir de cheval de Troie pour d'autres colonnes de
#     l'inscription (role, status…) ni pour l'inscription d'un AUTRE tournoi ;
#   • le panneau n'apparaît que là où il veut dire quelque chose.
class TournamentSeedingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner   = create_test_user(email: "owner-seed@example.com", first_name: "Alice", last_name: "Test")
    @intruder = create_test_user(email: "intrus-seed@example.com")
    @sport   = Sport.create!(name: "Ping seeding", slug: "ping-pong", icon: "🏓")
    @tournament = Tournament.create!(name: "Critérium chapeaux", sport: @sport, user: @owner,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     date: Date.tomorrow, place: "Salle test")
    @players = 8.times.map do |i|
      user = create_test_user(email: "seed#{i}@example.com")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
  end

  teardown { teardown_db }

  def seeding_params(overrides = {})
    { tournament: { pool_seeding_mode: "pots", seeded_pot_count: 2 }.merge(overrides) }
  end

  test "l'organisateur enregistre le mode et les chapeaux" do
    sign_in @owner

    patch seeding_tournament_path(@tournament), params: seeding_params(
      tournament_users_attributes: {
        "0" => { id: @players[0].id, pot: 1 },
        "1" => { id: @players[1].id, pot: 2 }
      }
    )

    assert_redirected_to tournament_path(@tournament)
    assert_equal "pots", @tournament.reload.pool_seeding_mode
    assert_equal 2, @tournament.seeded_pot_count
    assert_equal 1, @players[0].reload.pot
    assert_equal 2, @players[1].reload.pot
  end

  test "un joueur non organisateur ne peut pas toucher à la constitution" do
    sign_in @intruder

    patch seeding_tournament_path(@tournament), params: seeding_params

    assert_response :redirect
    assert_nil @tournament.reload.pool_seeding_mode
  end

  test "la constitution est verrouillée une fois le tournoi lancé" do
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
    sign_in @owner

    patch seeding_tournament_path(@tournament), params: seeding_params

    assert_response :redirect
    assert_nil @tournament.reload.pool_seeding_mode
  end

  test "seul le chapeau passe : les autres colonnes de l'inscription sont ignorées" do
    sign_in @owner

    patch seeding_tournament_path(@tournament), params: seeding_params(
      tournament_users_attributes: {
        "0" => { id: @players[0].id, pot: 1, role: "co_organisateur", status: "pending" }
      }
    )

    assert_equal 1, @players[0].reload.pot
    assert_equal "joueur", @players[0].role, "le rôle a été modifié par le formulaire de chapeaux"
    assert_equal "approved", @players[0].status
  end

  test "un chapeau invalide est refusé sans rien enregistrer" do
    sign_in @owner

    patch seeding_tournament_path(@tournament), params: seeding_params(
      tournament_users_attributes: { "0" => { id: @players[0].id, pot: 0 } }
    )

    assert_redirected_to tournament_path(@tournament)
    assert_nil @players[0].reload.pot
    assert_nil @tournament.reload.pool_seeding_mode, "un réglage a été enregistré malgré l'erreur"
  end

  test "le panneau s'affiche à l'organisateur avant le lancement, et pas après" do
    sign_in @owner
    get tournament_path(@tournament)
    assert_select "form.seeding-panel__form"

    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")

    get tournament_path(@tournament)
    assert_select "form.seeding-panel__form", count: 0
  end

  test "le panneau n'apparaît pas pour un format sans poules" do
    @tournament.update!(format: "ronde_suisse")
    sign_in @owner

    get tournament_path(@tournament)

    assert_select "form.seeding-panel__form", count: 0
  end
end
