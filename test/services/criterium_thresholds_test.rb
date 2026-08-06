require "test_helper"

# ── Tests Lot 6 — seuils d'effectif et variante « classement intégral » ───────
# Le règlement FFTT ne joue pas le même tournoi à 6, à 16 et à 32 joueurs. Ce
# fichier vérifie les deux moitiés de cette règle :
#
#   • le PLAN (pur, sans base) : combien de poules, de quelle taille, quelle
#     variante de phase finale — les seuils sont des paliers arbitraires du
#     document de référence, donc à confronter un par un ;
#   • le TOURNOI JOUÉ (avec base) : qu'un effectif réduit produise bien un tableau
#     unique où chaque place se joue, et qu'une poule unique se passe de phase
#     finale sans laisser le tournoi bloqué « en cours ».
#
# L'assertion qui compte le plus est la même qu'au Lot 5 : le classement final
# contient chaque joueur exactement une fois, et ses places se suivent SANS TROU.
# Les byes d'un tableau surdimensionné (11 joueurs dans un tableau de 16) laissent
# des places jamais jouées : sans compaction, le classement sauterait des rangs.
class CriteriumThresholdsTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping seuils", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-seuil-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # ── Le plan, sans toucher la base ───────────────────────────────────────────
  # `pool_plan` et `criterium_mode` acceptent un effectif en paramètre : ils sont
  # calculables sur un tournoi non enregistré, avant toute inscription.
  def planner(**attrs) = Tournament.new(format: "criterium_federal", **attrs)

  test "le plan de poules suit les seuils du règlement" do
    plans = {
      4  => [4],             # ≤ 7 : poule unique
      7  => [7],
      9  => [5, 4],          # 8-10 : 2 poules, équilibrées
      11 => [4, 4, 3],       # le cas nommé par le document
      14 => [4, 4, 3, 3],    # 12-16 : 4 poules
      20 => [4, 4, 4, 4, 4]  # ≥ 17 : règle générique (effectif / 4)
    }

    plans.each do |count, expected|
      assert_equal expected, planner.pool_plan(count), "plan incorrect pour #{count} joueurs"
      assert_equal count, planner.pool_plan(count).sum,
                   "le plan de #{count} joueurs n'accueille pas tout l'effectif"
    end
  end

  test "un réglage explicite de taille de poule remplace les seuils" do
    assert_equal [3, 3, 3, 3], planner(players_per_pool: 3).pool_plan(12)
    # 11 en poules de 3 : 4 poules, la dernière à 2 — l'organisateur a tranché.
    assert_equal [3, 3, 3, 2], planner(players_per_pool: 3).pool_plan(11)
  end

  test "la variante de phase finale est déduite de l'effectif" do
    assert_equal :none,     planner.criterium_mode(7)
    assert_equal :integral, planner.criterium_mode(8)
    assert_equal :integral, planner.criterium_mode(16)
    assert_equal :standard, planner.criterium_mode(17)
  end

  test "un mode explicite gagne toujours sur les seuils" do
    # C'est ce que font les tests des Lots 4 et 5 : jouer la variante standard à
    # 16 joueurs, effectif que les seuils enverraient en classement intégral.
    assert_equal :standard, planner(final_phase_mode: "standard").criterium_mode(16)
    assert_equal :integral, planner(final_phase_mode: "integral").criterium_mode(32)
  end

  test "un mode inconnu est refusé" do
    tournament = planner(name: "T", sport: @sport, max_players: 16, date: Date.tomorrow,
                         place: "Salle", final_phase_mode: "serpentin")

    assert_not tournament.valid?
    assert_includes tournament.errors.attribute_names, :final_phase_mode
  end

  test "le résumé de structure annonce la variante réellement appliquée" do
    assert_equal "Poule unique de 6, classement final = classement de poule",
                 summary_for(6)
    assert_equal "4 poules de 4 + tableau unique de 16, chaque place jouée",
                 summary_for(16)
    assert_equal "8 poules de 4, barrages, huitièmes + consolante",
                 summary_for(32)
  end

  test "le résumé n'annonce pas une taille de poule unique quand elles diffèrent" do
    # 11 joueurs → 4/4/3 : « 3 poules de 4 » serait faux pour le 11e joueur.
    assert_equal "3 poules (4-4-3) + tableau unique de 16, chaque place jouée",
                 summary_for(11)
  end

  # ── Le tournoi joué ─────────────────────────────────────────────────────────

  test "le tableau du classement intégral accueille tout l'effectif" do
    tournament = build_tournament(16)

    assert_equal :integral, tournament.criterium_mode
    # 2 sortants par poule donneraient un tableau de 8 : ici c'est 16.
    assert_equal 16, tournament.final_size
  end

  test "16 joueurs en classement intégral : 16 places, aucun ex æquo, aucun barrage" do
    tournament = play_all!(build_tournament(16))

    assert tournament.completed?, "le tournoi devrait être terminé"
    assert_empty tournament.barrage_rounds, "le classement intégral ne joue pas de barrage"
    assert_not tournament.tournament_rounds.consolation.exists?,
               "le classement intégral n'a pas de consolante"

    tiers = standings_of(tournament).tiers
    assert_equal (1..16).to_a, tiers.map(&:place)
    assert tiers.none?(&:tied?), "aucune place ne doit être partagée en classement intégral"
  end

  test "11 joueurs : poules 4/4/3 et classement final sans trou" do
    tournament = build_tournament(11)

    assert_equal [4, 4, 3], tournament.pool_plan
    TournamentEngine.for(tournament).next_round!
    # Le serpentin de PoolBuilder doit produire les mêmes TAILLES que le plan.
    assert_equal [3, 4, 4], tournament.reload.pools.values.map(&:size).sort

    tiers = standings_of(play_all!(tournament)).tiers
    placed = tiers.flat_map(&:players)

    # Un tableau de 16 pour 11 entrants laisse des places jamais jouées : la
    # compaction doit les absorber, donc 1..11 d'affilée et chacun une seule fois.
    assert_equal 11, placed.size
    assert_equal 11, placed.map(&:id).uniq.size
    assert_equal (1..11).to_a, tiers.flat_map { |tier| [tier.place] * tier.players.size }
  end

  test "6 joueurs : poule unique, aucune phase finale, classement = celui de la poule" do
    tournament = play_all!(build_tournament(6))

    assert_equal :none, tournament.criterium_mode
    assert_equal 1, tournament.pools.size
    assert_not tournament.final_phase_started?, "une poule unique ne joue aucune phase finale"
    assert_not tournament.bracket_expected?, "il n'y a pas de tableau à préfigurer"
    assert tournament.completed?, "tout est joué : le tournoi doit être terminé"

    # Le classement final EST le classement de la poule, dans le même ordre.
    fresh = Tournament.find(tournament.id)
    assert_equal fresh.ranked_pools[0].map(&:id),
                 fresh.standings.tiers.flat_map { |tier| tier.players.map(&:id) }
    assert_equal fresh.ranked_pools[0].first, fresh.champion
  end

  private

  def summary_for(count)
    Tournament.new(format: "criterium_federal", max_players: count).structure_summary
  end

  # Effectif seul : ni `players_per_pool` ni `final_phase_mode`, pour que ce soient
  # bien les SEUILS qui décident (c'est l'objet du lot).
  def build_tournament(count)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "criterium_federal", status: "open", max_players: count,
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "sl#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    # Le tirage au sort effectué par TournamentsController#start au lancement :
    # `draw_order` est la seule source d'aléa des moteurs.
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

  def play_all!(tournament, limit: 60)
    limit.times do
      TournamentEngine.for(tournament).next_round!
      break if tournament.reload.completed?

      pending_matches(tournament).each { |match| win_tournament_match!(match, match.player_a) }
    end
    tournament.reload
  end

  # Instance neuve : les classements sont memoïsés (cf. Tournament#reset_standings!).
  def standings_of(tournament) = Tournament.find(tournament.id).standings
end
