require "test_helper"

# ── Stabilité de l'ordre des joueurs (draw_order) ─────────────────────────────
# LeagueBuilder et PoolBuilder RECALCULENT leur calendrier round-robin à chaque
# appel de `next_round!` et ne persistent que la journée manquante. Ce design
# n'est correct que si l'ordre des joueurs est TOTAL, donc reproductible d'un
# appel à l'autre : si deux appels rendent deux ordres différents, le calendrier
# se décale en cours de route — certaines rencontres sont programmées deux fois,
# d'autres jamais, et la phase peut ne jamais se terminer.
#
# Or `ORDER BY draw_order` seul n'est pas un ordre total quand draw_order est nul
# (tournoi lancé avant la migration de 2026-07-29 : aucun backfill). Postgres est
# alors libre de rendre les lignes dans n'importe quel ordre, et ce n'est pas
# théorique — `recompute_stats_for` réécrit le bilan V/D de chaque joueur entre
# deux journées, ce qui déplace les tuples dans le heap et change l'ordre d'un
# seq scan.
#
# D'où le `:id` en second critère de tri. On ne teste PAS « deux lectures de suite
# rendent le même ordre » : sur une petite table fraîchement insérée, Postgres
# rend spontanément l'ordre d'insertion, donc un tel test passerait même sans le
# correctif. On déroule la phase en ENTIER et on compte les rencontres — c'est le
# seul symptôme qui se manifeste de façon fiable.
class DrawOrderStabilityTest < ActiveSupport::TestCase
  setup do
    @owner = create_test_user(email: "dos-owner@example.com")
    @sport = Sport.create!(name: "Ping stab", slug: "ping-pong", icon: "🏓")
  end

  teardown { teardown_db }

  # Tournoi dont AUCUN joueur n'a de draw_order — le cas des tournois legacy.
  def build_tournament(format:, count:, **attrs)
    tournament = Tournament.create!(name: "Stab #{format}", sport: @sport, user: @owner,
                                    format: format, status: "in_progress", max_players: count,
                                    date: Date.tomorrow, place: "Salle stab", **attrs)
    count.times do |i|
      user = create_test_user(email: "dos#{format}#{i}@example.com")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  # Déroule le tournoi jusqu'à son terme (ou `limit` itérations), en saisissant
  # tous les scores en attente entre chaque appel du moteur.
  def play_through!(tournament, limit: 30)
    limit.times do
      TournamentEngine.for(tournament).next_round!
      break if tournament.reload.completed?

      pending = TournamentMatch.joins(:tournament_round)
                               .where(tournament_rounds: { tournament_id: tournament.id })
                               .where(status: "pending", is_bye: false).to_a
      pending.each { |match| win_tournament_match!(match, match.player_a) }
    end
  end

  # Toutes les rencontres jouées dans une phase, sous forme de paires d'ids triées.
  def pairs_in(tournament, phase)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: tournament.id, phase: phase })
                   .where(is_bye: false)
                   .map { |m| [m.player_a_id, m.player_b_id].sort }
  end

  # L'invariant lui-même, plutôt que son symptôme : l'ORDER BY doit se terminer par
  # une colonne UNIQUE. C'est ce test qui échoue immédiatement si quelqu'un
  # réintroduit un `order(:draw_order)` seul — les tests de déroulé ci-dessous, eux,
  # ne le détectent qu'au gré du heap Postgres.
  test "l'ordre des joueurs des moteurs round-robin est total" do
    tournament = build_tournament(format: "poules", count: 4, players_per_pool: 4)

    [LeagueBuilder, PoolBuilder].each do |engine|
      sql = engine.new(tournament).send(:ordered_player_scope).to_sql
      order_by = sql[/ORDER BY (.+)\z/, 1].to_s

      assert_includes order_by, %("tournament_users"."draw_order"),
                      "#{engine} : le tirage au sort doit rester le critère principal"
      assert_includes order_by, %("tournament_users"."id"),
                      "#{engine} : ORDER BY sans colonne unique en dernier ressort → " \
                      "ordre non total, donc calendrier instable si draw_order est nul"
    end
  end

  test "un championnat sans draw_order programme chaque rencontre exactement une fois" do
    tournament = build_tournament(format: "championnat", count: 6, playoffs: false)
    play_through!(tournament)

    assert tournament.reload.completed?, "le championnat doit se terminer"

    pairs = pairs_in(tournament, "league")
    assert_equal pairs.size, pairs.uniq.size, "aucune rencontre ne doit être programmée deux fois"
    assert_equal 15, pairs.size, "6 joueurs → 15 rencontres (round-robin intégral)"
  end

  test "des poules sans draw_order programment chaque rencontre exactement une fois" do
    tournament = build_tournament(format: "poules", count: 8, players_per_pool: 4)
    play_through!(tournament)

    pairs = pairs_in(tournament, "pool")
    assert_equal pairs.size, pairs.uniq.size, "aucune rencontre de poule ne doit être doublée"
    # 2 poules de 4 → 6 rencontres chacune.
    assert_equal 12, pairs.size, "8 joueurs en 2 poules de 4 → 12 rencontres"

    # Et chaque poule doit être COMPLÈTE, sinon le classement de poule (donc les
    # sortants) serait calculé sur un round-robin tronqué.
    tournament.reload.pools.each_value do |members|
      expected = members.combination(2).map { |a, b| [a.id, b.id].sort }
      assert_equal expected.sort, (pairs & expected).sort,
                   "toutes les rencontres de la poule doivent avoir été programmées"
    end
  end

  test "les clés de tri survivent à un effectif où seuls certains ont un draw_order" do
    tournament = build_tournament(format: "ronde_suisse", count: 4)
    players = tournament.tournament_users.players.approved.order(:id).to_a
    # Effectif mixte : nil et entiers dans la même clé de tri → `nil <=> 1` vaut
    # nil, donc `sort_by` lève ArgumentError si la clé n'est pas défensive.
    players.first(2).each_with_index { |tu, index| tu.update_column(:draw_order, index) }

    assert_nothing_raised do
      tournament.reload.ranked_players
    end
    assert_nothing_raised do
      SwissPairing.new(tournament).build_pairs(tournament.reload.tournament_users.players.approved.to_a)
    end
  end
end
