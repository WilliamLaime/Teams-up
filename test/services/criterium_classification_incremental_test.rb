require "test_helper"

# ── Matchs de classement au fil de l'eau (Critérium Fédéral) ─────────────────
# Un mini-tableau de classement (5e-8e, 13e-16e…) ne s'ouvrait qu'une fois son
# tour source ENTIÈREMENT joué : un joueur battu en quart attendait le dernier
# quart du tableau pour savoir contre qui (et quand) il rejouerait.
#
# Désormais ses cases sont figées dès que le tour source existe, et chaque match
# naît dès que ses DEUX matchs nourriciers sont joués (appariement miroir : le
# perdant du match 1 contre celui du match 4 dans un tour de 4). Ce fichier
# vérifie :
#   • l'annonce du mini-tableau, et l'ordre causal (jamais avant son tour source) ;
#   • le match créé dès ses deux nourriciers, et pas avant ;
#   • un appariement IDENTIQUE à l'ancien mode quand personne ne déclare forfait ;
#   • qu'une correction ne détruit que l'aval concerné ;
#   • qu'un forfait ne gèle aucune branche, et que le tournoi se termine.
#
# 16 joueurs en 4 poules de 4 : tableau final de 8 (4 matchs au 1er tour), dont
# les perdants jouent les places 5 à 8 (« ok:5-8 », 2 matchs au 1er tour).
class CriteriumClassificationIncrementalTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping classement", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-cls-#{SecureRandom.hex(4)}@test.fr")
    @tournament = Tournament.create!(name: "Critérium classement", sport: @sport, user: @admin,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "cls#{i}-#{SecureRandom.hex(3)}@test.fr")
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

  # ── Annonce et ordre causal ─────────────────────────────────────────────────
  test "le mini-tableau des perdants est annoncé dès que son tour source existe" do
    open_final_bracket!

    places = classification_round("ok:5-8", 1)
    assert places.present?, "le 5e-8e doit exister dès que le 1er tour du tableau final existe"
    assert_equal 2, places.expected_matches
    assert_equal 0, places.tournament_matches.count, "aucun perdant n'est encore connu"
    assert_not places.complete?

    # Le 3e/4e se nourrit des demi-finales, qui n'existent pas encore : le créer
    # maintenant casserait l'ordre causal sur lequel repose #reconcile!.
    assert_nil classification_round("ok:3-4", 1)
  end

  test "les cases annoncent leur provenance, puis le joueur battu" do
    open_final_bracket!
    play_bracket_matches!(1, [0])

    first, second = flow.first_round_slots("ok:5-8").first
    helpers = ApplicationController.helpers
    assert_equal bracket_match(1, 0).loser, first.occupant, "le perdant du match 1 occupe déjà sa case"
    assert_nil helpers.bracket_slot_label(first)
    assert_equal "Perdant quart de finale 4", helpers.bracket_slot_label(second)
  end

  # ── Le cœur de la demande ───────────────────────────────────────────────────
  test "le match de classement naît dès que ses deux nourriciers sont joués" do
    open_final_bracket!
    play_bracket_matches!(1, [0, 3])

    places = classification_round("ok:5-8", 1)
    assert_equal 1, places.tournament_matches.count
    match = places.tournament_matches.first
    assert_equal 0, match.position
    assert_equal [bracket_match(1, 0).loser&.id, bracket_match(1, 3).loser&.id].to_set,
                 [match.player_a_id, match.player_b_id].to_set
    assert_not places.complete?
    assert TournamentMatchPolicy.new(match.player_a.user, match).update?,
           "le joueur doit pouvoir saisir le score de son match de classement"
  end

  test "deux nourriciers qui ne se font pas face ne créent aucun match" do
    open_final_bracket!
    play_bracket_matches!(1, [0, 1])

    assert_equal 0, classification_round("ok:5-8", 1).tournament_matches.count,
                 "le perdant du match 1 affronte celui du match 4, pas celui du match 2"
  end

  test "l'appariement est celui de l'ancien mode quand personne n'abandonne" do
    open_final_bracket!
    play_bracket_matches!(1, [0, 1, 2, 3])

    losers = bracket_round(1).tournament_matches.order(:position).map { |m| m.loser&.id }
    # Ancien mode : perdants dans l'ordre des positions, appariés en seeding 1 vs N.
    expected = BracketBuilder.seed_order(4).each_slice(2).map do |seed_a, seed_b|
      [losers[seed_a - 1], losers[seed_b - 1]].to_set
    end

    actual = classification_round("ok:5-8", 1).tournament_matches.order(:position)
                                              .map { |m| [m.player_a_id, m.player_b_id].to_set }
    assert_equal expected, actual
  end

  test "deux passes du moteur ne créent rien de plus" do
    open_final_bracket!
    play_bracket_matches!(1, [0, 3])

    count = match_count
    2.times { TournamentEngine.for(@tournament).next_round! }
    assert_equal count, match_count
  end

  # ── Correction de score ─────────────────────────────────────────────────────
  test "corriger un match détruit son aval, et seulement lui" do
    open_final_bracket!
    play_bracket_matches!(1, [0, 1, 2, 3])
    play_bracket_matches!(2, [0, 1])
    consolation_ids = @tournament.tournament_rounds.consolation.pluck(:id)

    corrected = bracket_match(1, 0)
    old_loser = corrected.loser
    win_tournament_match!(corrected, corrected.player_b)
    CriteriumFlow.new(Tournament.find(@tournament.id)).reconcile!(from: corrected.tournament_round)

    places = classification_round("ok:5-8", 1).tournament_matches
    assert places.none? { |m| [m.player_a_id, m.player_b_id].include?(old_loser.id) },
           "l'ancien perdant ne doit plus jouer les places 5 à 8"
    assert places.any? { |m| [m.player_a_id, m.player_b_id].include?(corrected.reload.loser&.id) },
           "le nouveau perdant doit y être replacé"
    assert_equal consolation_ids.sort, @tournament.tournament_rounds.consolation.pluck(:id).sort,
                 "la consolante n'a rien à voir avec la correction"
  end

  # ── Forfaits et liveness ────────────────────────────────────────────────────
  test "un forfait au tableau final donne un bye à son adversaire de classement" do
    open_final_bracket!
    quitter = bracket_match(1, 3).player_b
    WithdrawPlayer.new(Tournament.find(@tournament.id), quitter).call!
    play_bracket_matches!(1, [0])

    match = classification_round("ok:5-8", 1).tournament_matches.find_by(position: 0)
    assert match.present?, "la case du partant ne doit pas geler le match"
    assert match.is_bye
    assert_equal bracket_match(1, 0).loser&.id, match.player_a_id
  end

  # Le partant quitte le tournoi APRÈS les poules mais AVANT que son match de
  # consolante soit posé : ce match devient un bye, sans perdant. Sa case du
  # mini-tableau en aval ne doit pas rester vide, sinon une position n'aurait
  # jamais de match et le tournoi ne se terminerait jamais.
  test "un bye né d'un forfait ne gèle pas le mini-tableau en aval" do
    reach_barrages!
    fourth = @tournament.pool_standings.values.first.qualifier(4)
    WithdrawPlayer.new(Tournament.find(@tournament.id), fourth).call!

    play_all!

    assert @tournament.reload.completed?, "le tournoi doit se terminer"
    assert_equal(16, @tournament.standings.tiers.sum { |tier| tier.players.size })
  end

  test "un tournoi mené jusqu'au bout se termine et classe chacun une seule fois" do
    play_all!

    assert @tournament.reload.completed?
    placed = @tournament.standings.tiers.flat_map(&:players)
    assert_equal 16, placed.size
    assert_equal placed.uniq.size, placed.size, "aucun joueur ne doit être classé deux fois"
  end

  # L'effectif de l'Open d'Automne-Hiver : poules mixtes (4 et 3), donc une
  # consolante avec des exemptions structurelles et des mini-tableaux incomplets.
  test "29 inscrits : chaque mini-tableau s'annonce tôt et le tournoi se termine" do
    @tournament.update!(max_players: 32)
    13.times do |i|
      user = create_test_user(email: "cls-extra#{i}-#{SecureRandom.hex(3)}@test.fr")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved",
                                           draw_order: 16 + i)
    end

    open_final_bracket!
    assert classification_round("ok:9-16", 1).present?, "le 9e-16e doit s'annoncer avec les 8es"

    play_all!

    assert @tournament.reload.completed?, "le tournoi doit se terminer"
    placed = @tournament.standings.tiers.flat_map(&:players)
    assert_equal 29, placed.size
    assert_equal placed.uniq.size, placed.size, "aucun joueur ne doit être classé deux fois"
  end

  private

  def flow =CriteriumFlow.new(Tournament.find(@tournament.id))

  def match_count
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id }).count
  end

  def bracket_rounds = @tournament.tournament_rounds.bracket.main_branch.ordered.to_a
  def bracket_round(number) = bracket_rounds.find { |round| round.number == number }
  def bracket_match(number, position) = bracket_round(number).tournament_matches.find_by(position: position)

  def classification_round(key, number)
    @tournament.tournament_rounds.classification.find_by(branch: key, number: number)
  end

  def resolve_pending_except_bracket!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(tournament_rounds: { phase: %w[pool barrage] })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  # Poules jouées, barrages créés mais pas encore joués.
  def reach_barrages!
    30.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.barrage_rounds.exists?

      TournamentMatch.joins(:tournament_round)
                     .where(tournament_rounds: { tournament_id: @tournament.id, phase: "pool" })
                     .where(status: "pending", is_bye: false)
                     .to_a
                     .each { |match| win_tournament_match!(match, match.player_a) }
    end
    raise "barrages non créés" unless @tournament.barrage_rounds.exists?
  end

  # Poules et barrages joués : le 1er tour du tableau final est entièrement posé,
  # aucun de ses matchs n'est joué. La consolante, elle, n'est pas touchée.
  def open_final_bracket!
    30.times do
      TournamentEngine.for(@tournament).next_round!
      first = bracket_round(1)
      break if first && first.tournament_matches.count == first.expected_matches

      resolve_pending_except_bracket!
    end
    raise "tableau final non ouvert" if bracket_round(1).blank?
  end

  # Joue UNIQUEMENT les positions demandées d'un tour du tableau final, puis
  # relaie au moteur comme le fait TournamentMatchesController#update.
  def play_bracket_matches!(number, positions)
    bracket_round(number).tournament_matches.order(:position).each do |match|
      next unless positions.include?(match.position)
      next unless match.status == "pending"

      win_tournament_match!(match, match.player_a)
    end
    TournamentEngine.for(@tournament).next_round!
  end

  def play_all!
    80.times do
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
