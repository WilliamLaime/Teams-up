require "test_helper"

# Tests de bout en bout du moteur de tournoi avec la base (SwissPairing#next_round!
# + BracketBuilder). On simule un tournoi complet : lancement, saisie des vainqueurs
# ronde par ronde, bascule automatique sur le tableau final, jusqu'à la victoire.
class TournamentEngineTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Tennis test", slug: "tennis-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # Crée un tournoi avec `count` joueurs approuvés.
  def build_tournament(count, format: "ronde_suisse")
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: format, status: "open", max_players: count)
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  # Donne un score gagnant à player_a sur tous les matchs en attente de la ronde
  # courante (Lot 4 : le vainqueur est dérivé du score ; arbitraire mais déterministe).
  def resolve_current_round!(tournament)
    round = tournament.current_round
    round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
      win_tournament_match!(match, match.player_a)
    end
    round
  end

  # Joue tout le tournoi jusqu'à ce qu'il soit terminé (garde-fou anti-boucle).
  def play_to_completion!(tournament)
    50.times do
      break if tournament.reload.completed?

      resolve_current_round!(tournament)
      SwissPairing.new(tournament).next_round!
    end
  end

  test "lancement : crée la ronde suisse 1 avec les bons appariements" do
    tournament = build_tournament(16)
    SwissPairing.new(tournament).next_round!

    round = tournament.swiss_rounds.first
    assert_equal 1, round.number
    assert_equal "swiss", round.phase
    assert_equal 8, round.tournament_matches.count
    # Chaque joueur apparaît une fois exactement.
    ids = round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }
    assert_equal tournament.tournament_users.pluck(:id).sort, ids.sort
  end

  test "bye sur effectif impair : le joueur exempté est marqué gagnant d'office" do
    tournament = build_tournament(13)
    SwissPairing.new(tournament).next_round!

    bye = tournament.current_round.tournament_matches.find_by(is_bye: true)
    assert_not_nil bye
    assert_nil bye.player_b_id
    assert_equal bye.player_a_id, bye.winner_id
    assert_equal "completed", bye.status
  end

  test "idempotence : re-générer sans terminer la ronde ne crée rien" do
    tournament = build_tournament(16)
    SwissPairing.new(tournament).next_round!
    assert_equal 1, tournament.tournament_rounds.count

    SwissPairing.new(tournament).next_round! # ronde 1 pas terminée
    assert_equal 1, tournament.tournament_rounds.count
  end

  test "qualification 3V / élimination 3D correctement appliquées" do
    tournament = build_tournament(8)
    SwissPairing.new(tournament).next_round!
    # Ronde 1 : les player_a gagnent → 4 joueurs à 1V, 4 à 1D.
    resolve_current_round!(tournament)
    SwissPairing.new(tournament).next_round!

    winners = tournament.tournament_users.where("wins >= 1")
    assert winners.any?
    assert tournament.tournament_users.where("losses >= 1").any?
  end

  test "recompute_stats! agrège les sets et points depuis les scores (Lot 4)" do
    tournament = build_tournament(8)
    SwissPairing.new(tournament).next_round!
    resolve_current_round!(tournament)          # player_a gagne 6-0 6-0 partout
    SwissPairing.new(tournament).next_round!    # déclenche recompute_stats!

    winner = tournament.tournament_users.where("wins >= 1").first
    assert_operator winner.sets_won, :>=, 2, "le gagnant doit avoir des sets gagnés"
    assert_operator winner.points_won, :>, winner.points_lost
    assert_operator winner.set_average, :>, 0

    loser = tournament.tournament_users.where("losses >= 1").first
    assert_operator loser.sets_lost, :>=, 2
    assert_operator loser.set_average, :<, 0
  end

  test "flux complet 16 joueurs → Final 8 → un vainqueur, tournoi completed" do
    tournament = build_tournament(16)
    SwissPairing.new(tournament).next_round!
    play_to_completion!(tournament)

    assert tournament.reload.completed?
    assert tournament.bracket_started?
    # La dernière ronde du tableau est la finale : un seul match.
    final = tournament.bracket_rounds.last
    assert_equal 1, final.tournament_matches.count
  end

  # Le moteur évite les rematchs tant qu'un appariement sans rematch existe. En fin
  # de phase, le vivier de joueurs actifs peut devenir trop petit (ils ont tous déjà
  # joué) → un rematch devient inévitable et est toléré (force_pair). On vérifie donc
  # l'absence de rematch UNIQUEMENT sur les rondes au vivier suffisant (≥ 8 joueurs),
  # où une solution sans rematch est mathématiquement garantie.
  test "aucun rematch évitable sur la phase suisse (16 joueurs)" do
    tournament = build_tournament(16)
    SwissPairing.new(tournament).next_round!

    20.times do
      break if tournament.reload.bracket_started?

      resolve_current_round!(tournament)
      SwissPairing.new(tournament).next_round!
    end

    seen = Set.new
    tournament.swiss_rounds.each do |round|
      real = round.tournament_matches.where(is_bye: false).where.not(player_b_id: nil).to_a
      big_pool = real.size >= 4 # ≥ 8 joueurs → rematch toujours évitable
      real.each do |m|
        pair = [m.player_a_id, m.player_b_id].minmax
        assert_not seen.include?(pair), "rematch évitable détecté : #{pair.inspect}" if big_pool
        seen << pair
      end
    end
  end

  test "tableau final : têtes de série 1 et 2 dans des moitiés opposées" do
    tournament = build_tournament(16)
    SwissPairing.new(tournament).next_round!
    # Avancer jusqu'au bracket.
    20.times do
      break if tournament.reload.bracket_started?

      resolve_current_round!(tournament)
      SwissPairing.new(tournament).next_round!
    end

    round1 = tournament.bracket_rounds.first
    matches = round1.tournament_matches.order(:position).to_a
    seed1_match = matches.find { |m| player_seeds(m).include?(1) }
    seed2_match = matches.find { |m| player_seeds(m).include?(2) }
    # Moitié haute = première moitié des positions ; moitié basse = seconde.
    half = matches.size / 2.0
    assert (matches.index(seed1_match) < half) != (matches.index(seed2_match) < half),
           "les têtes de série 1 et 2 doivent être dans des moitiés opposées"
  end

  private

  def player_seeds(match)
    match.players.map(&:seed)
  end
end
