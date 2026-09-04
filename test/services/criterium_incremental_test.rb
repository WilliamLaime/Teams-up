require "test_helper"

# ── Progression anticipée du tableau (Critérium Fédéral) ─────────────────────
# Un Critérium s'étale dans le temps : attendre que TOUS les huitièmes soient
# joués avant de créer les quarts immobilise le tableau derrière la rencontre la
# plus lente. BracketBuilder en mode incrémental crée donc chaque match dès que
# ses deux nourriciers sont joués.
#
# Ce fichier vérifie les quatre choses qui pourraient casser à cette occasion :
#   • le match devient réellement JOUABLE (le tour partiel n'est pas verrouillé) ;
#   • aucune place n'est attribuée à tort (un tour partiel n'est pas une finale) ;
#   • le moteur reste idempotent et le tournoi finit toujours par se terminer ;
#   • une correction de score ne détruit plus l'aval qui n'a rien à voir.
class CriteriumIncrementalTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping incr", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-inc-#{SecureRandom.hex(4)}@test.fr")
    @tournament = Tournament.create!(name: "Critérium incrémental", sport: @sport, user: @admin,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "inc#{i}-#{SecureRandom.hex(3)}@test.fr")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
    open_final_bracket!
  end

  def teardown
    teardown_db
  end

  # ── Le cœur de la demande ───────────────────────────────────────────────────
  test "deux matchs joués sur quatre suffisent à créer le match du tour suivant" do
    play_bracket_matches!(1, [0, 1])

    quarters = bracket_round(2)
    assert quarters.present?, "le tour 2 devait naître des deux premiers matchs joués"
    assert_equal 1, quarters.tournament_matches.count, "un seul match est créable"
    assert_equal 0, quarters.tournament_matches.first.position
    assert_equal 2, quarters.expected_matches
    assert_not quarters.complete?, "un tour à 1 match sur 2 attendus n'est pas terminé"
  end

  test "le tour partiel n'est pas verrouillé : le match créé est jouable" do
    play_bracket_matches!(1, [0, 1])

    quarters = bracket_round(2)
    assert_not_equal "completed", quarters.status
    match = quarters.tournament_matches.first
    # C'est LA régression bloquante : un tour clos rend ses matchs injouables.
    assert TournamentMatchPolicy.new(match.player_a.user, match).update?,
           "le joueur doit pouvoir saisir le score de son match"

    # Et le tour nourricier, lui, n'est pas terminé non plus.
    assert_not bracket_round(1).complete?
  end

  test "on peut jouer le tour 2 avant que l'autre moitié du tour 1 soit jouée" do
    play_bracket_matches!(1, [0, 1])
    play_bracket_matches!(2, [0])

    assert_nil bracket_round(3), "la finale n'a qu'un adversaire connu"

    play_bracket_matches!(1, [2, 3])
    quarters = bracket_round(2)
    assert_equal 2, quarters.tournament_matches.count
    assert_equal [0, 1], quarters.tournament_matches.order(:position).map(&:position)

    play_bracket_matches!(2, [1])
    assert bracket_round(3).present?, "la finale naît des deux matchs du tour 2"
  end

  # ── Aucune place attribuée à tort ───────────────────────────────────────────
  test "un tour partiel n'attribue aucune place et ne termine pas le tournoi" do
    play_bracket_matches!(1, [0, 1])
    play_bracket_matches!(2, [0])

    assert_empty @tournament.standings.decided_tiers,
                 "aucun tableau n'a livré de finale : aucune place ne doit être décidée"
    assert_not @tournament.reload.completed?
  end

  # ── Idempotence ─────────────────────────────────────────────────────────────
  test "rejouer le moteur ne crée rien de plus" do
    play_bracket_matches!(1, [0, 1])
    before = match_count

    5.times { TournamentEngine.for(@tournament).next_round! }

    assert_equal before, match_count
    positions = bracket_round(2).tournament_matches.map(&:position)
    assert_equal positions.uniq, positions
  end

  # ── Correction de score ─────────────────────────────────────────────────────
  # C'est ici que la lecture POSITIONNELLE de CriteriumFlow#stale? se paie : un
  # tour aval partiel compte moins de joueurs que le tour amont n'en annonce, donc
  # une comparaison d'ENSEMBLES le déclarerait périmé et le détruirait — avec son
  # score — alors qu'il n'a rien à voir avec la correction.
  test "corriger un match ne détruit pas le tour suivant né d'une autre moitié" do
    play_bracket_matches!(1, [0, 1, 2])
    play_bracket_matches!(2, [0])

    kept = bracket_round(2).tournament_matches.order(:position).first
    assert_equal 1, bracket_round(2).tournament_matches.count, "le tour 2 doit être partiel"
    kept_winner = kept.winner_id

    # On corrige le match 2, qui nourrit l'AUTRE position du tour 2.
    corrected = bracket_round(1).tournament_matches.order(:position).third
    win_tournament_match!(corrected, corrected.player_b)
    CriteriumFlow.new(@tournament).reconcile!(from: corrected.tournament_round)

    survivor = bracket_round(2).tournament_matches.order(:position).first
    assert_equal kept.id, survivor.id, "le match déjà joué ne devait pas être détruit"
    assert_equal kept_winner, survivor.winner_id, "son score devait survivre"
  end

  # ── Liveness ────────────────────────────────────────────────────────────────
  test "un tournoi mené jusqu'au bout se termine et classe tout le monde" do
    play_all!

    assert @tournament.reload.completed?, "le tournoi doit se terminer"
    assert_equal 16, @tournament.standings.tiers.sum { |tier| tier.players.size }
  end

  private

  def match_count
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id }).count
  end

  def bracket_rounds = @tournament.tournament_rounds.bracket.main_branch.ordered.to_a
  def bracket_round(number) = bracket_rounds.find { |round| round.number == number }

  def resolve_pending_except_bracket!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where.not(tournament_rounds: { phase: "bracket" })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  # Poules + barrages joués, tableau final ouvert et intact : c'est l'état depuis
  # lequel toutes les assertions de ce fichier partent.
  def open_final_bracket!
    30.times do
      TournamentEngine.for(@tournament).next_round!
      break if bracket_round(1).present?

      resolve_pending_except_bracket!
    end
    raise "tableau final non ouvert" if bracket_round(1).blank?
  end

  # Joue UNIQUEMENT les positions demandées d'un tour du tableau final, puis
  # relaie au moteur comme le fait TournamentMatchesController#update.
  def play_bracket_matches!(number, positions)
    round = bracket_round(number)
    raise "tour #{number} absent" if round.blank?

    round.tournament_matches.order(:position).each do |match|
      next unless positions.include?(match.position)
      next unless match.status == "pending"

      win_tournament_match!(match, match.player_a)
    end
    TournamentEngine.for(@tournament).next_round!
  end

  def play_all!
    60.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.reload.completed?

      TournamentMatch.joins(:tournament_round)
                     .where(tournament_rounds: { tournament_id: @tournament.id })
                     .where(status: "pending", is_bye: false)
                     .to_a
                     .each { |match| win_tournament_match!(match, match.player_a) }
    end
  end
end
