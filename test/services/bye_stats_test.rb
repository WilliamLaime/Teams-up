require "test_helper"

# ── Le bye ne doit pas gonfler le bilan V/D d'un joueur ────────────────────────
# Un effectif impair oblige le calendrier round-robin à mettre un joueur au repos
# à chaque journée : c'est un « bye » (TournamentMatch#is_bye), qu'on clôture avec
# `winner_id = player_a` pour que la journée puisse se terminer (cf. #resolve_bye).
#
# Ce vainqueur technique n'est PAS une victoire sportive. En poules et en
# championnat, un bye n'est qu'un tour de repos : le compter offrirait une victoire
# gratuite à tout joueur d'une poule de 3, fausserait le classement affiché, et —
# parce que le seeding du tableau final lit ces mêmes colonnes via
# Tournament#rank_key — avantagerait mécaniquement les poules impaires.
#
# La ronde suisse est le cas INVERSE, et c'est volontaire : un bye y vaut 1 point
# par convention (le joueur exempté ne doit pas être puni du hasard des
# appariements), et le seuil de qualification à 3 V en dépend.
class ByeStatsTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Tennis test", slug: "tennis-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  def build_tournament(count, format:, **attrs)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: format, status: "open", max_players: count,
                                    date: Date.tomorrow, place: "Terrain test", **attrs)
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  # Joue toutes les journées de poule (le joueur A gagne : arbitraire mais
  # déterministe), sans jamais toucher aux byes — ils sont déjà clôturés.
  def play_pool_phase!(tournament)
    10.times do
      round = tournament.reload.current_round
      break if round.nil? || round.phase != "pool"

      round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
        win_tournament_match!(match, match.player_a)
      end
      TournamentEngine.for(tournament).next_round!
    end
  end

  test "poules de 3 : le bye ne compte ni en victoire ni en match joué" do
    tournament = build_tournament(9, format: "poules", players_per_pool: 3)
    TournamentEngine.for(tournament).next_round!
    play_pool_phase!(tournament)

    # Une poule de 3 se joue en 2 matchs par joueur, point — la 3e journée est un
    # bye. Sans le filtre, chaque joueur afficherait 3 rencontres au bilan.
    byes = tournament.tournament_matches.where(is_bye: true).count
    assert_equal 9, byes, "chaque joueur d'une poule de 3 doit avoir exactement un bye"

    tournament.tournament_users.players.approved.each do |tu|
      assert_equal 2, tu.wins + tu.losses + tu.draws,
                   "#{tu.display_name} : 2 matchs réellement joués attendus, " \
                   "le bye a été compté au bilan (#{tu.wins}V-#{tu.losses}D)"
      assert_operator tu.wins, :<=, 2, "#{tu.display_name} ne peut pas gagner plus de 2 matchs"
    end
  end

  test "poules de 3 : le perdant de ses deux matchs reste à 0 victoire" do
    tournament = build_tournament(9, format: "poules", players_per_pool: 3)
    TournamentEngine.for(tournament).next_round!
    play_pool_phase!(tournament)

    # Le symptôme observé en recette : un joueur battu partout affiché à 1 V.
    losers = tournament.tournament_users.players.approved.select { |tu| tu.losses == 2 }
    assert losers.any?, "la poule de 3 doit produire au moins un joueur battu deux fois"
    losers.each do |tu|
      assert_equal 0, tu.wins, "#{tu.display_name} n'a gagné aucun match, il ne peut pas être à #{tu.wins} V"
    end
  end

  test "ronde suisse : le bye reste une victoire (convention du format)" do
    tournament = build_tournament(9, format: "ronde_suisse")
    SwissPairing.new(tournament).next_round!

    round = tournament.swiss_rounds.first
    bye = round.tournament_matches.find_by(is_bye: true)
    assert bye, "un effectif impair doit produire un bye en ronde suisse"

    round.tournament_matches.where(is_bye: false).find_each do |match|
      win_tournament_match!(match, match.player_a)
    end
    SwissPairing.new(tournament).recompute_stats_for("swiss", apply_state: true, count_byes: true)

    assert_equal 1, bye.player_a.reload.wins,
                 "en ronde suisse le joueur exempté marque son point : le bye vaut une victoire"
  end
end
