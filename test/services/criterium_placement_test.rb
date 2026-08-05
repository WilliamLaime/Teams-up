require "test_helper"

# ── Tests Lot 5 — consolante, matchs de classement, places finales ────────────
# Le Lot 4 a validé les barrages et le tableau final. Ici on vérifie ce qui fait
# la spécificité du règlement FFTT : CHAQUE place est jouée (sauf les ex æquo que
# le règlement prévoit explicitement), les mini-tableaux de classement tournent EN
# PARALLÈLE, et le tournoi ne se termine qu'une fois la dernière branche jouée.
#
# L'assertion la plus forte du fichier est la bijection : réunis, les rangs du
# classement final contiennent chaque joueur exactement une fois. C'est elle qui
# prouve qu'aucun joueur n'est perdu ni compté deux fois — l'erreur la plus facile
# à commettre dans une topologie à 11 tableaux imbriqués.
class CriteriumPlacementTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping place", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-place-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # `final_phase_mode: "standard"` explicite : les seuils d'effectif du Lot 6
  # basculeraient sinon un tournoi de 16 joueurs en classement intégral, sans
  # barrage ni consolante. Les places jouées ici sont celles de la variante standard.
  def build_tournament(count, players_per_pool: 4, final_phase_mode: "standard")
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "criterium_federal", status: "open", max_players: count,
                                    players_per_pool: players_per_pool,
                                    final_phase_mode: final_phase_mode,
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "pl#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    # Le tirage au sort effectué par TournamentsController#start au lancement.
    tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    tournament.update!(status: "in_progress")
    tournament
  end

  def pending_matches(tournament)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
  end

  # Déroule le tournoi de bout en bout. `limit` est un garde-fou : si le moteur
  # cessait de progresser, on veut un échec d'assertion lisible, pas une boucle
  # infinie.
  def play_all!(tournament, limit: 60)
    limit.times do
      TournamentEngine.for(tournament).next_round!
      break if tournament.reload.completed?

      matches = pending_matches(tournament)
      # Plus rien à jouer et toujours pas terminé → on laisse le moteur créer la
      # suite au tour de boucle suivant.
      matches.each { |match| win_tournament_match!(match, match.player_a) }
    end
    tournament.reload
  end

  # Joue les poules puis les barrages, et s'arrête dès que le tableau final existe.
  def play_until_bracket!(tournament, limit: 30)
    limit.times do
      TournamentEngine.for(tournament).next_round!
      break if tournament.reload.bracket_rounds.exists?

      pending_matches(tournament).each { |match| win_tournament_match!(match, match.player_a) }
    end
    tournament.reload
  end

  def branches_of(tournament, phase)
    tournament.tournament_rounds.where(phase: phase).pluck(:branch).uniq.sort
  end

  def standings_of(tournament) = Tournament.find(tournament.id).standings

  # ── Consolante ──────────────────────────────────────────────────────────────

  test "la consolante s'ouvre avec les 4es de poule et les perdants de barrage" do
    tournament = build_tournament(16)
    play_until_bracket!(tournament)

    consolation = tournament.tournament_rounds.consolation.main_branch.ordered.first
    assert consolation.present?, "la consolante doit s'ouvrir en même temps que le tableau final"

    entrants = consolation.tournament_matches.flat_map { |m| [m.player_a, m.player_b] }.compact
    assert_equal 8, entrants.size, "4 poules → 4 quatrièmes + 4 perdants de barrage"

    fourths = tournament.pool_standings.values.filter_map { |pool| pool.qualifier(4) }
    barrage_losers = tournament.barrage_rounds.first.tournament_matches.filter_map(&:loser)

    assert_equal (fourths + barrage_losers).map(&:id).sort, entrants.map(&:id).sort,
                 "la consolante ne doit contenir QUE les 4es de poule et les perdants de barrage"
  end

  test "en poules de 3 la consolante ne contient que les perdants de barrage" do
    tournament = build_tournament(12, players_per_pool: 3)
    play_until_bracket!(tournament)

    consolation = tournament.tournament_rounds.consolation.main_branch.ordered.first
    entrants = consolation.tournament_matches.flat_map { |m| [m.player_a, m.player_b] }.compact

    assert_equal 4, entrants.size, "4 poules de 3 → 4 perdants de barrage, pas de 4e de poule"
    assert_equal tournament.barrage_rounds.first.tournament_matches.filter_map(&:loser).map(&:id).sort,
                 entrants.map(&:id).sort
  end

  # ── Matchs de classement ────────────────────────────────────────────────────

  test "les branches de classement du tableau final sont créées en parallèle" do
    tournament = build_tournament(16)
    play_all!(tournament)

    # Tableau final de 8 (4 poules × 2) → places 1-8 : 3e/4e, 5e-8e et 7e/8e.
    assert_equal %w[ok:3-4 ok:5-8 ok:7-8], branches_of(tournament, "classification") & %w[ok:3-4 ok:5-8 ok:7-8],
                 "les trois branches de classement du tableau final doivent exister"

    # Le point du plan : 3e/4e et 5e-8e ne s'attendent pas l'un l'autre. Ils sont
    # tous deux au tour n°1 de la phase classification — c'est exactement ce que la
    # colonne `branch` rend possible.
    ok34 = tournament.tournament_rounds.find_by(phase: "classification", branch: "ok:3-4", number: 1)
    ok58 = tournament.tournament_rounds.find_by(phase: "classification", branch: "ok:5-8", number: 1)
    assert ok34.present? && ok58.present?, "deux branches concurrentes au même numéro de tour"
  end

  test "le mini-tableau des places 5 à 8 rejoue les quatre places" do
    tournament = build_tournament(16)
    play_all!(tournament)

    # 4 perdants de quart → 2 demies (tour 1), puis la finale 5e/6e (tour 2), et
    # les perdants des demies jouent la 7e place dans leur propre branche.
    rounds = tournament.tournament_rounds.where(phase: "classification", branch: "ok:5-8").ordered
    assert_equal 2, rounds.count, "un tableau de 4 se joue en 2 tours"
    assert_equal 2, rounds.first.tournament_matches.count
    assert_equal 1, rounds.last.tournament_matches.count, "le tour 2 est la finale 5e/6e"

    ok78 = tournament.tournament_rounds.where(phase: "classification", branch: "ok:7-8").ordered
    assert_equal 1, ok78.count
    assert_equal 1, ok78.first.tournament_matches.count, "un seul match pour la 7e place"
  end

  # ── Places finales ──────────────────────────────────────────────────────────

  test "16 joueurs : chaque place de 1 à 16 est jouée, aucun ex æquo" do
    tournament = build_tournament(16)
    play_all!(tournament)

    assert tournament.completed?, "le tournoi doit être terminé"

    tiers = standings_of(tournament).tiers
    assert_equal (1..16).to_a, tiers.map(&:place),
                 "16 places distinctes : à 4 poules de 4, le règlement ne prévoit aucun ex æquo"
    assert tiers.none?(&:tied?), "aucun rang partagé"
  end

  test "le classement final contient chaque joueur exactement une fois" do
    tournament = build_tournament(16)
    play_all!(tournament)

    placed = standings_of(tournament).tiers.flat_map(&:players)
    expected = tournament.approved_players.map(&:id).sort

    assert_equal expected, placed.map(&:id).sort,
                 "bijection : aucun joueur perdu, aucun classé deux fois"
  end

  test "32 joueurs : mapping exact du règlement, ex æquo inclus" do
    tournament = build_tournament(32)
    play_all!(tournament, limit: 80)

    assert tournament.completed?, "le tournoi doit être terminé"

    tiers = standings_of(tournament).tiers
    # Tableau final de 16 → places 1-8 jouées, puis 9es ex æquo (8 joueurs).
    # Consolante de 16 → places 17-24 jouées, puis 25es ex æquo (8 joueurs).
    assert_equal (1..8).to_a, tiers.select { |t| t.place <= 8 }.map(&:place)
    assert_equal [17, 18, 19, 20, 21, 22, 23, 24],
                 tiers.map(&:place).select { |place| place.between?(17, 24) }

    tied = tiers.select(&:tied?)
    assert_equal [9, 25], tied.map(&:place), "deux paliers d'ex æquo : les 9es et les 25es"
    assert_equal [8, 8], tied.map { |tier| tier.players.size }

    assert_equal 32, tiers.sum { |tier| tier.players.size }, "somme des rangs = effectif"
    assert_equal tournament.approved_players.map(&:id).sort,
                 tiers.flat_map(&:players).map(&:id).sort
  end

  test "le libellé d'un palier d'ex æquo l'annonce" do
    tournament = build_tournament(32)
    play_all!(tournament, limit: 80)

    tier = standings_of(tournament).tiers.find(&:tied?)
    assert_equal "9es ex æquo", tier.label
    assert_equal "1er", standings_of(tournament).tiers.first.label
  end

  # ── Fin de tournoi ──────────────────────────────────────────────────────────

  test "le tournoi n'est pas terminé tant qu'une branche reste à jouer" do
    tournament = build_tournament(16)
    play_until_bracket!(tournament)

    # On joue le tableau final jusqu'à sa finale, SANS toucher aux autres branches.
    20.times do
      break if tournament.reload.bracket_rounds.count >= 3

      tournament.bracket_rounds.flat_map { |r| r.tournament_matches.where(status: "pending") }
                .each { |match| win_tournament_match!(match, match.player_a) }
      TournamentEngine.for(tournament).next_round!
    end

    final = tournament.reload.bracket_rounds.last
    final.tournament_matches.each { |match| win_tournament_match!(match, match.player_a) }
    TournamentEngine.for(tournament).next_round!

    refute tournament.reload.completed?,
           "la finale du tableau final est jouée, mais la consolante et les classements non"
    assert tournament.tournament_rounds.final_phase.any? { |round| !round.complete? },
           "il doit rester des tours à jouer"
  end

  test "le champion est le vainqueur du tableau final, pas celui d'un match de classement" do
    tournament = build_tournament(16)
    play_all!(tournament)

    ok_final = tournament.bracket_rounds.last.tournament_matches.first
    assert_equal ok_final.winner.id, tournament.champion.id
    assert_equal 1, standings_of(tournament).place_of(ok_final.winner)

    # Le vainqueur de la finale 5e/6e est bien 5e, pas champion.
    fifth = tournament.tournament_rounds.where(phase: "classification", branch: "ok:5-8")
                      .ordered.last.tournament_matches.first.winner
    assert_equal 5, standings_of(tournament).place_of(fifth)
    refute_equal fifth.id, tournament.champion.id
  end

  # ── Idempotence, encore ─────────────────────────────────────────────────────

  test "advance! reste idempotent avec toutes les branches ouvertes" do
    tournament = build_tournament(16)
    play_until_bracket!(tournament)

    before = TournamentMatch.joins(:tournament_round)
                            .where(tournament_rounds: { tournament_id: tournament.id }).count
    3.times { TournamentEngine.for(tournament).next_round! }
    after = TournamentMatch.joins(:tournament_round)
                           .where(tournament_rounds: { tournament_id: tournament.id }).count

    assert_equal before, after, "trois appels de plus ne doivent créer aucun match"
  end

  # ── Correction d'un score de poule ──────────────────────────────────────────
  # `bracket_rounds` ne désigne que le tableau final : détruire « le tableau final »
  # laisserait barrages, consolante et classements en place, calculés depuis un
  # classement de poule devenu faux. Le tournoi afficherait alors un tableau
  # contredisant ses propres poules.
  test "corriger un résultat de poule reconstruit toute la phase finale" do
    tournament = build_tournament(16)
    play_until_bracket!(tournament)

    assert tournament.tournament_rounds.final_phase.count > 1, "il faut une phase finale à invalider"

    pool_match = TournamentMatch.joins(:tournament_round)
                                .where(tournament_rounds: { tournament_id: tournament.id, phase: "pool" })
                                .where(is_bye: false).first
    loser = pool_match.loser

    # On inverse le vainqueur de ce match de poule, comme le fait l'action `correct`.
    win_tournament_match!(pool_match, loser)
    TournamentRound.where(id: pool_match.tournament_round_id).update_all(status: "in_progress")
    tournament.tournament_rounds.final_phase.destroy_all
    TournamentEngine.for(Tournament.find(tournament.id)).next_round!

    tournament.reload
    assert tournament.tournament_rounds.final_phase.any?,
           "la phase finale doit être reconstruite par le réconciliateur"
    assert_equal loser.id, pool_match.reload.winner_id, "la correction doit avoir tenu"

    # Et le tournoi doit pouvoir aller jusqu'au bout après correction.
    play_all!(tournament)
    assert tournament.reload.completed?
    assert_equal (1..16).to_a, standings_of(tournament).tiers.map(&:place)
  end

  test "aucune rencontre n'est programmée deux fois sur un tournoi complet" do
    tournament = build_tournament(16)
    play_all!(tournament)

    pairs = TournamentMatch.joins(:tournament_round)
                           .where(tournament_rounds: { tournament_id: tournament.id })
                           .where(is_bye: false)
                           .map { |m| [m.id, [m.player_a_id, m.player_b_id].sort] }

    duplicated = pairs.map(&:last).tally.select { |_pair, count| count > 1 }
    # Deux joueurs peuvent se rencontrer en poule PUIS en phase finale : on ne
    # vérifie donc l'unicité qu'à l'intérieur de la phase finale.
    final_pairs = TournamentMatch.joins(:tournament_round)
                                 .where(tournament_rounds: { tournament_id: tournament.id,
                                                             phase: Tournament::FINAL_PHASES })
                                 .where(is_bye: false)
                                 .map { |m| [m.player_a_id, m.player_b_id].sort }

    assert_equal final_pairs.uniq.size, final_pairs.size,
                 "en phase finale, deux joueurs ne doivent pas se rencontrer deux fois " \
                 "(doublons toutes phases confondues : #{duplicated.keys.size})"
  end
end
