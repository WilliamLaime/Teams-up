require "test_helper"

# ── Tests ForfeitMatch ────────────────────────────────────────────────────────
# Règle du Critérium (confirmée par l'organisateur) :
#   • en POULE, un forfait ne vaut que pour le match : le joueur dispute tous ses
#     matchs suivants, reste classé et garde son accès à la phase finale ;
#   • en phase finale, un forfait vaut pour le RESTE du tournoi, matchs de
#     classement compris.
class ForfeitMatchTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping forfait", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
    @tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "f#{i}-#{SecureRandom.hex(3)}@test.fr")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
    advance!
  end

  def teardown
    teardown_db
  end

  def advance! = TournamentEngine.for(@tournament).next_round!

  def pending_matches
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(status: "pending", is_bye: false)
  end

  def pending_match_of(player)
    pending_matches.find_by("player_a_id = :id OR player_b_id = :id", id: player.id)
  end

  # Résout tous les matchs en attente (player_a gagne), puis fait avancer le tournoi.
  def resolve_all!
    pending_matches.to_a.each { |m| win_tournament_match!(m, m.player_a) }
    advance!
  end

  def pool_standing_of(player) = Tournament.find(@tournament.id).pool_standings[player.reload.pool]

  # Les matchs de poule d'un joueur, dans l'ordre des journées.
  def pool_matches_of(player)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id, phase: "pool" }, is_bye: false)
                   .where("player_a_id = :id OR player_b_id = :id", id: player.id)
                   .order("tournament_rounds.number")
                   .to_a
  end

  test "poule de 4 : un forfait au 2e match ne bloque pas le 3e, et le joueur reste classé" do
    player = @tournament.tournament_users.players.where(pool: 0).order(:draw_order).first
    first, second, third = pool_matches_of(player)

    # 1er match : joué et gagné.
    win_tournament_match!(first, player)

    # 2e match : forfait en cours de partie (l'adversaire mène 11-3, 6-4).
    opponent = second.opponent_of(player)
    partial = second.player_a_id == player.id ? [[3, 11], [4, 6]] : [[11, 3], [6, 4]]
    assert ForfeitMatch.new(@tournament, second, player, sets: partial).call!
    second.reload
    assert_equal opponent.id, second.winner_id
    assert_equal [3, 0], [second.sets_won_by(opponent), second.sets_won_by(player)]
    assert_equal "active", player.reload.state, "un forfait de poule ne retire pas le joueur du tournoi"

    # 3e match : toujours à jouer, SANS forfait d'office.
    third.reload
    refute third.forfeit?
    assert_equal "pending", third.status
    win_tournament_match!(third, player)
    resolve_all!

    row = pool_standing_of(player).row_for(player)
    assert_equal 3, row.played
    assert_equal 2 + 0 + 2, row.points, "2 victoires (2 pts chacune) + 1 forfait (0 pt)"
    assert @tournament.barrage_rounds.exists?, "la poule se termine normalement"
  end

  test "poule : un joueur qui cumule deux forfaits reste classé et entre en phase finale selon son rang" do
    player = @tournament.tournament_users.players.where(pool: 1).order(:draw_order).first

    pool_matches_of(player).first(2).each do |match|
      assert ForfeitMatch.new(@tournament, match, player).call!
      match.reload
      assert_equal [0, 3], [match.sets_won_by(player), match.sets_won_by(match.opponent_of(player))]
    end
    resolve_all! # le 3e match se joue, puis toutes les poules se terminent

    refute player.reload.withdrawn?
    place = pool_standing_of(player).place_of(player)
    assert_not_nil place, "toujours classé dans sa poule"
    in_final_phase = TournamentMatch.joins(:tournament_round)
                                    .where(tournament_rounds: { tournament_id: @tournament.id, phase: "barrage" })
                                    .where("player_a_id = :id OR player_b_id = :id", id: player.id)
                                    .exists?
    assert_equal [2, 3].include?(place), in_final_phase,
                 "un 2e ou 3e de poule joue le barrage, forfaits ou pas"
  end

  test "phase finale : un forfait vaut pour le reste du tournoi" do
    20.times do
      break if @tournament.barrage_rounds.exists?

      resolve_all!
    end
    barrage = @tournament.barrage_rounds.first.tournament_matches.where(is_bye: false).first
    player = barrage.player_b

    assert ForfeitMatch.new(@tournament, barrage, player).call!

    assert player.reload.withdrawn?, "forfait en phase finale = forfait pour la suite"
    assert_equal barrage.player_a_id, barrage.reload.winner_id
    # Le perdant de barrage descend normalement en consolante : pas lui.
    60.times do
      break if Tournament.find(@tournament.id).completed?

      resolve_all!
    end
    later = TournamentMatch.joins(:tournament_round)
                           .where(tournament_rounds: { tournament_id: @tournament.id })
                           .where.not(tournament_rounds: { phase: %w[pool barrage] })
                           .where("player_a_id = :id OR player_b_id = :id", id: player.id)
    assert_empty later.to_a, "aucun match de consolante ni de classement pour un joueur forfait"
  end
end
