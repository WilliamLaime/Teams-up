require "test_helper"

# ── Tableau final et consolante au fil des barrages (Critérium Fédéral) ──────
# Demande des joueurs : un match du tableau final (ou de la consolante) doit se
# jouer dès que SON barrage est fini, sans attendre les autres barrages.
#
# Ce fichier vérifie les trois promesses qui rendent cela possible :
#   • les cases du premier tour sont réservées dès la fin des poules ;
#   • un barrage joué pose aussitôt ses deux matchs (vainqueur et perdant) ;
#   • la case d'un barragiste ne dépend PAS de l'issue des barrages — sinon un
#     match déjà posé serait à la mauvaise place une fois le suivant joué.
class CriteriumBarrageFlowTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping fil", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-fil-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # ── Le cœur de la demande ───────────────────────────────────────────────────

  test "dès la fin des poules, les deux tableaux ont leurs cases mais aucun match" do
    tournament = play_pools!(build_tournament(16))

    # 4 poules : 4 1ers face à 4 vainqueurs de barrage, 4 perdants face à 4 4es.
    # Chaque match dépend d'un barrage : rien n'est encore jouable.
    [bracket_round(tournament), consolation_round(tournament)].each do |round|
      assert round.present?, "le tour doit être réservé dès la création des barrages"
      assert_equal 4, round.expected_matches
      assert_equal 0, round.tournament_matches.count
      assert_not round.complete?
    end
  end

  test "un barrage joué pose aussitôt son match au tableau final et en consolante" do
    tournament = play_pools!(build_tournament(16))
    barrage = barrages(tournament).first

    win_tournament_match!(barrage, barrage.player_a)
    advance!(tournament)

    bracket_matches = bracket_round(tournament).tournament_matches.to_a
    consolation_matches = consolation_round(tournament).tournament_matches.to_a

    assert_equal 1, bracket_matches.size, "seul le match de ce barrage est connu"
    assert_includes bracket_matches.first.players, barrage.player_a
    assert_equal 1, consolation_matches.size
    assert_includes consolation_matches.first.players, barrage.player_b

    # Un vrai match, jouable tout de suite — les autres barrages restent à jouer.
    match = bracket_matches.first
    assert_not match.is_bye
    assert_equal "pending", match.status
    assert TournamentMatchPolicy.new(match.player_a.user, match).update?
    assert_equal(3, barrages(tournament).count { |m| m.status == "pending" })
  end

  test "le match posé se joue et fait avancer le tableau sans attendre les autres barrages" do
    tournament = play_pools!(build_tournament(16))
    barrages(tournament).first(2).each { |barrage| win_tournament_match!(barrage, barrage.player_a) }
    advance!(tournament)

    bracket_round(tournament).tournament_matches.each { |match| win_tournament_match!(match, match.player_a) }
    advance!(tournament)

    assert_not bracket_round(tournament).complete?, "deux barrages restent à jouer"
    assert_not tournament.reload.completed?
    assert_equal(2, barrages(tournament).count { |m| m.status == "pending" })
  end

  test "rejouer le moteur ne pose rien de plus" do
    tournament = play_pools!(build_tournament(16))
    barrage = barrages(tournament).first
    win_tournament_match!(barrage, barrage.player_a)
    advance!(tournament)
    before = TournamentMatch.joins(:tournament_round).where(tournament_rounds: { tournament_id: tournament.id }).count

    3.times { advance!(tournament) }

    assert_equal before,
                 TournamentMatch.joins(:tournament_round).where(tournament_rounds: { tournament_id: tournament.id }).count
  end

  # ── Des cases indépendantes des résultats ───────────────────────────────────

  test "la case d'un barragiste est celle annoncée avant le barrage, quel que soit le vainqueur" do
    tournament = play_pools!(build_tournament(32))
    announced  = { "ok" => slot_positions(tournament, "ok"), "ko" => slot_positions(tournament, "ko") }

    # Un barrage sur deux gagné par le 3e : les deux issues sont couvertes.
    barrages(tournament).each_with_index do |barrage, index|
      win_tournament_match!(barrage, index.even? ? barrage.player_a : barrage.player_b)
    end
    advance!(tournament)

    barrages(tournament).each do |barrage|
      { "ok" => [:winner, bracket_round(tournament)], "ko" => [:loser, consolation_round(tournament)] }
        .each do |key, (camp, round)|
        player   = barrage.public_send(camp)
        position = announced[key].fetch([barrage.id, camp])
        assert_includes round.tournament_matches.find_by!(position: position).players, player,
                        "#{key} : le #{camp} du barrage n'est pas à la case annoncée"
      end
    end
  end

  test "aucun 1er de poule ne retombe sur sa poule, même quand le 3e gagne le barrage" do
    %i[player_a player_b].each do |camp|
      tournament = play_pools!(build_tournament(32))
      barrages(tournament).each { |barrage| win_tournament_match!(barrage, barrage.public_send(camp)) }
      advance!(tournament)

      firsts = Tournament.find(tournament.id).pool_standings.values.to_set { |pool| pool.qualifier(1).id }
      bracket_round(tournament).tournament_matches.reject(&:is_bye).each do |match|
        first, promoted = match.players.partition { |tu| firsts.include?(tu.id) }.map(&:first)
        next if first.nil? || promoted.nil?

        assert_not_equal first.pool, promoted.pool, "barrages gagnés par #{camp} : collision de poule"
      end
    end
  end

  # ── Forfait ─────────────────────────────────────────────────────────────────

  test "un 1er parti avant son match laisse un bye au vainqueur du barrage" do
    tournament = play_pools!(build_tournament(16))
    barrage    = barrages(tournament).first
    slot_pair  = CriteriumFlow.new(tournament).first_round_slots("ok")
                              .find { |pair| pair.compact.any? { |slot| slot.barrage&.id == barrage.id } }
    first      = slot_pair.compact.find(&:player).player

    WithdrawPlayer.new(tournament, first).call!
    win_tournament_match!(barrage.reload, barrage.player_a)
    advance!(tournament)

    match = bracket_round(tournament).tournament_matches.find { |m| m.players.include?(barrage.player_a) }
    assert match.present?, "le vainqueur du barrage doit entrer au tableau"
    assert match.is_bye, "son adversaire est parti : il passe sans jouer"
  end

  private

  def build_tournament(count)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "criterium_federal", status: "open", max_players: count,
                                    players_per_pool: 4, final_phase_mode: "standard",
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "fil#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    tournament.update!(status: "in_progress")
    tournament
  end

  # Joue les poules et s'arrête dès que les barrages existent (sans les jouer).
  def play_pools!(tournament)
    20.times do
      advance!(tournament)
      break if tournament.barrage_rounds.exists?

      TournamentMatch.joins(:tournament_round)
                     .where(tournament_rounds: { tournament_id: tournament.id })
                     .where(status: "pending", is_bye: false)
                     .find_each { |match| win_tournament_match!(match, match.player_a) }
    end
    tournament.reload
  end

  def advance!(tournament) = TournamentEngine.for(tournament).next_round!

  def barrages(tournament) = tournament.barrage_rounds.first.tournament_matches.order(:position).to_a

  def bracket_round(tournament) = tournament.tournament_rounds.bracket.main_branch.find_by(number: 1)

  def consolation_round(tournament) = tournament.tournament_rounds.consolation.main_branch.find_by(number: 1)

  # { [id du barrage, :winner|:loser] => position annoncée au 1er tour }.
  def slot_positions(tournament, key)
    CriteriumFlow.new(tournament).first_round_slots(key).each_with_index.with_object({}) do |(pair, position), index|
      pair.compact.select(&:barrage).each { |slot| index[[slot.barrage.id, slot.camp]] = position }
    end
  end
end
