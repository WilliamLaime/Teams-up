require "test_helper"

# ── Forfaits en phase finale de Critérium (Lot 8) ─────────────────────────────
# Un abandon en cours de tournoi ne doit jamais bloquer la mécanique. C'est le cas
# par construction — WithdrawPlayer est agnostique de la phase, et BracketBuilder
# crée tous ses matchs via build_match!, qui pose un forfait dès qu'un des deux
# joueurs est `withdrawn`. « Par construction » n'est pas une preuve : ce fichier
# vérifie les deux moments où ça pourrait casser.
#
#   • le match en cours du partant → forfait immédiat, son adversaire continue ;
#   • les tableaux ouverts APRÈS son départ → il n'y entre plus (cf.
#     CriteriumFlow#resolve : il s'arrête là où il s'est arrêté), mais la branche
#     doit rester vivante — son adversaire y est exempté et prend la place. Sans
#     cela le tableau resterait ouvert pour toujours et le tournoi ne se
#     terminerait jamais.
class CriteriumForfeitTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping forfait", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-ff-#{SecureRandom.hex(4)}@test.fr")
    @tournament = Tournament.create!(name: "Critérium forfait", sport: @sport, user: @admin,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "ff#{i}-#{SecureRandom.hex(3)}@test.fr")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
  end

  def teardown
    teardown_db
  end

  test "l'abandon d'un demi-finaliste n'entre plus dans le match pour la 3e place" do
    play_until_bracket_round!(2)
    semi = bracket_round(2).tournament_matches.order(:position).first
    quitter = semi.player_a

    WithdrawPlayer.new(@tournament, quitter).call!

    # 1. Sa demi-finale est perdue par forfait, son adversaire monte en finale.
    #    C'est là qu'il s'est arrêté, et ça ne change pas.
    semi.reload
    assert semi.forfeit?, "la demi-finale du partant devait passer en forfait"
    assert_equal semi.player_b_id, semi.winner_id

    # 2. La branche « places 3-4 » doit rester VIVANTE — sans elle le tournoi ne
    #    se terminerait jamais — mais le partant n'y entre plus : l'autre perdant
    #    de demi-finale y est exempté et prend la 3e place, qu'il a bel et bien
    #    gagnée sur le terrain.
    play_all!
    third_place = classification_matches("ok:3-4").first
    assert third_place.present?, "la branche « places 3-4 » n'a pas été ouverte"
    assert_not_includes [third_place.player_a_id, third_place.player_b_id], quitter.id,
                        "un joueur parti n'entre pas dans un tableau ouvert après son forfait"
    assert third_place.is_bye, "le seul prétendant restant doit être exempté"
    assert_equal 3, @tournament.standings.place_of(third_place.winner)

    # 3. Personne n'est perdu du classement, et le partant y figure DERNIER :
    #    aucun tableau ne lui a attribué de place, il tombe donc dans la queue,
    #    derrière tous ceux qui sont allés au bout.
    assert @tournament.reload.completed?, "le tournoi doit se terminer"
    standings = @tournament.standings
    assert_equal 16, standings.tiers.sum { |tier| tier.players.size }
    assert_equal 16, standings.place_of(quitter), "un joueur parti finit dernier"
  end

  test "un tournoi dont un finaliste abandonne se termine quand même" do
    play_until_bracket_round!(2)
    play_all!
    # On abandonne une fois tout joué : le classement doit rester complet et le
    # tournoi conclu, pas rouvert par un état « withdrawn » de dernière minute.
    finalist = Tournament.find(@tournament.id).champion

    WithdrawPlayer.new(@tournament, finalist).call!

    assert @tournament.reload.completed?, "le tournoi ne doit pas rouvrir sur un abandon tardif"
    tiers = Tournament.find(@tournament.id).standings.tiers
    assert_equal 16, tiers.sum { |tier| tier.players.size }, "un joueur a disparu du classement"
  end

  private

  def bracket_rounds = @tournament.tournament_rounds.bracket.main_branch.ordered.to_a
  def bracket_round(number) = bracket_rounds.find { |round| round.number == number }

  def classification_matches(branch)
    @tournament.tournament_rounds.where(phase: "classification", branch: branch)
               .ordered.flat_map { |round| round.tournament_matches.order(:position).to_a }
  end

  def resolve_all_pending!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  def play_until_bracket_round!(number)
    30.times do
      TournamentEngine.for(@tournament).next_round!
      break if bracket_round(number).present?

      resolve_all_pending!
    end
    raise "tableau final incomplet" if bracket_round(number).blank?
  end

  def play_all!
    60.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.reload.completed?

      resolve_all_pending!
    end
  end
end
