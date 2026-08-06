require "test_helper"

# ── Correction d'un score en phase finale de Critérium (Lot 8) ────────────────
# Une correction détruit l'aval devenu faux, puis le laisse se reconstruire. Toute
# la question est : jusqu'où va « l'aval » ?
#
# En POULE, le classement de départ change : barrages, tableau final, consolante,
# matchs de classement — tout est caduc, il faut tout reprendre.
#
# DANS la phase finale, non : les branches sont parallèles. Corriger un quart de
# finale du tableau principal ne dit rien de la consolante, qui oppose d'autres
# joueurs. Ce fichier vérifie exactement cette frontière — que le nécessaire est
# détruit, et que rien de plus ne l'est.
class CriteriumCorrectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = create_test_user(email: "owner-corr@example.com", first_name: "Alice", last_name: "Test")
    @sport = Sport.create!(name: "Ping correction", slug: "ping-pong", icon: "🏓")
    # 16 joueurs en variante standard : barrages + tableau de 8 + consolante de 8.
    # Sans `final_phase_mode`, les seuils du règlement (Lot 6) enverraient cet
    # effectif en classement intégral, qui n'a ni barrage ni consolante.
    @tournament = Tournament.create!(name: "Critérium correction", sport: @sport, user: @owner,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "cc#{i}@example.com")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
    sign_in @owner
  end

  teardown { teardown_db }

  test "corriger un quart du tableau final laisse la consolante intacte" do
    play_until_bracket_round!(2) # les quarts sont joués, les demies existent

    quarter = bracket_round(1).tournament_matches.order(:position).first
    assert consolation_round(1).present?, "la consolante doit exister pour que ce test ait un sens"
    consolation_before = round_signature(consolation_round(1))
    semis_before       = round_signature(bracket_round(2))
    loser              = other_player(quarter)

    correct!(quarter, loser)

    assert_equal loser.id, quarter.reload.winner_id, "la correction n'a pas pris"
    # La consolante est une autre branche, alimentée par les barrages : elle n'a
    # aucune raison d'être touchée, ni détruite ni rejouée.
    assert_equal consolation_before, round_signature(consolation_round(1)),
                 "la consolante a été détruite ou rebâtie par une correction du tableau final"
    # Les demi-finales, en revanche, opposaient le vainqueur d'hier : reconstruites.
    assert_not_equal semis_before, round_signature(bracket_round(2)),
                     "les demi-finales n'ont pas été reconstruites"
    assert_includes participants(bracket_round(2)), loser.id
  end

  test "les scores déjà saisis en consolante survivent à la correction" do
    play_until_bracket_round!(2)
    # On joue un match de consolante AVANT la correction : c'est lui qui ne doit
    # pas disparaître.
    assert consolation_round(1).present?, "la consolante doit exister pour que ce test ait un sens"
    consolation_match = consolation_round(1).tournament_matches.order(:position).reject(&:is_bye).first
    win_tournament_match!(consolation_match, consolation_match.player_a) if consolation_match.status != "completed"
    survivor = consolation_match.reload.winner_id

    quarter = bracket_round(1).tournament_matches.order(:position).first
    correct!(quarter, other_player(quarter))

    assert_equal survivor, consolation_match.reload.winner_id,
                 "un score de consolante a été effacé par une correction du tableau final"
  end

  test "corriger un match de poule reprend toute la phase finale" do
    play_until_bracket_round!(1)
    assert @tournament.tournament_rounds.final_phase.exists?

    pool_match = @tournament.tournament_rounds.where(phase: "pool").first
                            .tournament_matches.order(:position).first
    correct!(pool_match, other_player(pool_match))

    # Le classement de poule ayant changé, les barrages eux-mêmes sont refaits :
    # aucun tour de phase finale d'avant la correction ne doit survivre tel quel.
    assert @tournament.reload.tournament_rounds.final_phase.exists?,
           "la phase finale doit être reconstruite immédiatement"
    assert_equal 1, @tournament.barrage_rounds.count, "les barrages ont été dupliqués"
  end

  test "une correction sans changement de vainqueur ne détruit rien" do
    play_until_bracket_round!(2)

    quarter = bracket_round(1).tournament_matches.order(:position).first
    semis_before = round_signature(bracket_round(2))
    winner = quarter.winner

    correct!(quarter, winner) # même vainqueur, score différent

    assert_equal winner.id, quarter.reload.winner_id
    assert_equal semis_before, round_signature(bracket_round(2)),
                 "l'aval a été reconstruit alors que le vainqueur n'a pas changé"
  end

  test "le tournoi terminé repasse en cours quand la correction rouvre le tableau" do
    play_all!
    assert @tournament.reload.completed?

    final = bracket_rounds.last.tournament_matches.first
    correct!(final, other_player(final))

    assert_equal other_player(final).id, final.reload.winner_id
    # Le champion change : le tournoi est rejoué jusqu'à sa conclusion, et le
    # classement final suit — c'est le réconciliateur qui reconclut, pas un état figé.
    assert @tournament.reload.completed?, "tout est joué : le tournoi doit se reconclure"
    assert_equal final.reload.winner_id, Tournament.find(@tournament.id).champion.id
  end

  # ── Onglet Classement ───────────────────────────────────────────────────────
  # Non-régression : la vue lisait le classement COMPLET, qui range par position de
  # poule les joueurs qu'aucun tableau n'a encore classés. Dès la fin des poules,
  # l'onglet affichait donc un « Classement final » de 16 joueurs en 4 rangs d'ex
  # æquo — le classement des poules recopié juste au-dessus des tables de poules.
  test "l'onglet Classement n'annonce aucune place tant qu'aucune n'est jouée" do
    play_until_bracket_round!(1)

    get tournament_path(@tournament)
    assert_response :success
    assert_select ".tournament-ranking__pool-title", text: /Classement final|Places déjà acquises/,
                  count: 0, message: "aucune place n'est jouée : rien à annoncer"
    # Les tables de poules, elles, restent bien là — c'est le seul classement qui
    # ait un sens à ce stade.
    assert_select ".tournament-ranking__pool-title", text: /Poule A/
  end

  # Les barrages n'ont qu'un tour : la colonne de ruban de 300 px tronquait les
  # noms (« G... ») en laissant les trois quarts de la page vides.
  test "la phase Barrages étale ses matchs en grille sur toute la largeur" do
    play_until_bracket_round!(1)

    get tournament_path(@tournament)
    assert_response :success
    assert_select ".round-ribbon--wide" do
      assert_select ".round-col__matches--grid .tmatch-card", 4,
                    "4 poules → 4 barrages, rangés en grille"
    end
    # Les poules gardent leur ruban paginé : la grille ne doit pas déborder dessus.
    assert_select ".round-ribbon--paginated .round-col__matches--grid", 0
  end

  test "l'onglet Classement affiche le classement final une fois le tournoi terminé" do
    play_all!
    assert @tournament.reload.completed?

    get tournament_path(@tournament)
    assert_select ".tournament-ranking__pool-title", text: /Classement final/
    # 16 joueurs, 16 places jouées : une ligne par joueur, aucun badge « ex æquo ».
    assert_select ".tournament-ranking__table" do |tables|
      final = tables.first
      assert_equal 16, final.css("tbody tr").size
      assert_equal 0, final.css(".tournament-ranking__tie").size
    end
  end

  private

  # ── Manipulation du tournoi ─────────────────────────────────────────────────

  def correct!(match, winner)
    rules  = match.scoring_rules
    needed = match.sets_to_win
    set    = winner.id == match.player_a_id ? [rules[:target], 0] : [0, rules[:target]]
    sets   = Array.new(needed) { set.dup }

    patch correct_tournament_tournament_match_path(@tournament, match), params: {
      tournament_match: { games_a: sets.map(&:first), games_b: sets.map(&:last) }
    }
  end

  def other_player(match)
    match.winner_id == match.player_a_id ? match.player_b : match.player_a
  end

  def resolve_all_pending!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  # Déroule le tournoi jusqu'à ce que le tableau final ait `number` tours.
  def play_until_bracket_round!(number)
    30.times do
      TournamentEngine.for(@tournament).next_round!
      break if bracket_rounds.size >= number && bracket_round(number).present?

      resolve_all_pending!
    end
    # Le tour visé doit exister, et tous les précédents être joués.
    raise "tableau final incomplet" if bracket_round(number).blank?
  end

  def play_all!
    60.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.reload.completed?

      resolve_all_pending!
    end
  end

  # ── Lecture ─────────────────────────────────────────────────────────────────

  def bracket_rounds = @tournament.tournament_rounds.bracket.main_branch.ordered.to_a
  def bracket_round(number) = bracket_rounds.find { |round| round.number == number }

  def consolation_round(number)
    @tournament.tournament_rounds.consolation.ordered.find { |round| round.number == number }
  end

  def participants(round)
    round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact.sort
  end

  # Signature d'un tour : qui s'y affronte ET qui a gagné. Deux tours de même
  # signature sont interchangeables — c'est ce qui distingue « reconstruit à
  # l'identique » de « détruit puis rejoué autrement ».
  def round_signature(round)
    return nil if round.blank?

    round.tournament_matches.order(:position).map do |match|
      [match.player_a_id, match.player_b_id, match.winner_id]
    end
  end
end
