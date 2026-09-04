require "test_helper"

# ── Rendu du board d'un Critérium Fédéral ─────────────────────────────────────
# CriteriumFlow est testé unitairement (test/services/criterium_flow_test.rb) ;
# ici on vérifie que la page se rend RÉELLEMENT à chaque étape du format. Sans ce
# filet, une phase nouvelle (barrages) pourrait n'être affichée nulle part, ou un
# libellé de tour lever une exception, sans qu'aucun test ne le voie.
class CriteriumBoardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = create_test_user(email: "owner-crit@example.com", first_name: "Alice", last_name: "Test")
    @sport = Sport.create!(name: "Ping board", slug: "ping-pong", icon: "🏓")
    @tournament = Tournament.create!(name: "Critérium test", sport: @sport, user: @owner,
                                     format: "criterium_federal", status: "open", max_players: 16,
                                     players_per_pool: 4, final_phase_mode: "standard",
                                     date: Date.tomorrow, place: "Salle test")
    16.times do |i|
      user = create_test_user(email: "cb#{i}@example.com")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    @tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    @tournament.update!(status: "in_progress")
  end

  teardown { teardown_db }

  def resolve_all_pending!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  def play_until_barrages!
    TournamentEngine.for(@tournament).next_round!
    20.times do
      break if @tournament.barrage_rounds.exists?

      resolve_all_pending!
      TournamentEngine.for(@tournament).next_round!
    end
  end

  # Déroule le tournoi jusqu'à son terme : toutes les branches, jusqu'au dernier
  # match de classement.
  def play_all!
    60.times do
      TournamentEngine.for(@tournament).next_round!
      break if @tournament.reload.completed?

      resolve_all_pending!
    end
  end

  test "le board se rend pendant la phase de poules" do
    TournamentEngine.for(@tournament).next_round!

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "[data-phase=?]", "main"
    # Les barrages sont PRÉFIGURÉS dès le lancement (cases « À déterminer »), comme
    # le tableau final : la structure est connue d'avance, une rencontre par poule.
    # Ce test exigeait l'inverse — la section et sa pastille surgissaient à la fin
    # des poules, sans qu'on ait jamais vu ce qui attendait.
    assert_select "section[data-phase=?] .tmatch-card--placeholder", "barrage", 4,
                  "4 poules → 4 barrages préfigurés"
    assert_select "section[data-phase='barrage'] .tmatch-card:not(.tmatch-card--placeholder)", 0,
                  "aucun barrage réel avant la fin des poules"
  end

  # La consolante est la moitié de l'effectif et la moitié des places. Elle
  # n'apparaissait qu'à l'ouverture du tableau final, alors que les barrages et le
  # tableau final, eux, étaient préfigurés dès le lancement : les joueurs qui y
  # atterrissent ne voyaient donc rien de ce qui les attendait.
  test "la consolante est préfigurée dès le lancement, comme le tableau final" do
    TournamentEngine.for(@tournament).next_round!

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".phase-nav__pill[data-phase=?]", "consolation"
    assert_select "section[data-phase=?] .tournament-phase__title", "consolation",
                  text: /Consolante/
    assert_select "section[data-phase='consolation'] .tmatch-card:not(.tmatch-card--placeholder)", 0,
                  "aucun match réel de consolante avant la fin des barrages"
    # Sans provenance à afficher sur la 1re colonne, la note dit qui viendra y jouer.
    assert_select "section[data-phase='consolation'] .tournament-empty",
                  text: /4es de poule/
  end

  # Les effectifs réduits n'ont ni barrage ni consolante (tableau unique) : la
  # pastille ouvrirait une section vide.
  test "aucune pastille Consolante en classement intégral" do
    @tournament.update!(final_phase_mode: "integral")
    TournamentEngine.for(@tournament).next_round!

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".phase-nav__pill[data-phase=?]", "consolation", 0
    assert_select "section[data-phase=?]", "consolation", 0
  end

  test "le board affiche une section et une pastille Barrages une fois les poules terminées" do
    play_until_barrages!
    assert @tournament.barrage_rounds.exists?, "les barrages doivent exister pour ce test"

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "section[data-phase=?] .tournament-phase__title", "barrage", text: "Barrages"
    assert_select ".phase-nav__pill[data-phase=?]", "barrage"
    # La phase affichée par défaut doit être la plus avancée.
    assert_select "[data-tournament-phase-switch-default-value=?]", "barrage"
  end

  test "le board se rend une fois le tableau final démarré, et bascule dessus par défaut" do
    play_until_barrages!
    resolve_all_pending!
    TournamentEngine.for(@tournament).next_round!
    assert @tournament.reload.bracket_started?

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select "[data-tournament-phase-switch-default-value=?]", "bracket"
    # La consolante s'ouvre EN MÊME TEMPS que le tableau final (mêmes sources : les
    # barrages), donc quatre pastilles dès ce moment : poules, barrages, tableau,
    # consolante. Les matchs de classement, eux, naissent des perdants du 1er tour.
    assert_select ".phase-nav__pill[data-phase=?]", "consolation"
    assert_select ".phase-nav__pill", 4
    assert_select "section[data-phase=?] .tournament-phase__title", "consolation"
  end

  test "le board affiche les matchs de classement une fois le tournoi déroulé" do
    play_all!
    assert @tournament.reload.completed?, "le tournoi doit être terminé pour ce test"

    sign_in @owner
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".phase-nav__pill[data-phase=?]", "classification"
    assert_select "section[data-phase=?] .tournament-phase__title", "classification",
                  text: "Matchs de classement"
    # Un bloc par branche, titré par la plage de places qu'il attribue.
    assert_select "section[data-phase='classification'] .tournament-phase__subtitle",
                  text: "Match pour la 3e place"
    assert_select ".phase-nav__pill", 5
  end

  test "l'onglet Classement se rend avec le barème points-parties du règlement" do
    play_until_barrages!

    sign_in @owner
    get tournament_path(@tournament, tab: "ranking")

    assert_response :success
  end

  test "l'onglet Classement affiche les places finales une fois le tournoi terminé" do
    play_all!

    sign_in @owner
    get tournament_path(@tournament, tab: "ranking")

    assert_response :success
    assert_select ".tournament-ranking__pool-title", text: "Classement final"
    # 16 joueurs, 4 poules de 4 → chaque place est jouée, donc aucun badge ex æquo.
    assert_select ".tournament-ranking__tie", count: 0
  end

  test "le résumé de structure d'un Critérium mentionne barrages et consolante" do
    assert_match(/poules de 4/, @tournament.structure_summary)
    assert_match(/barrages/, @tournament.structure_summary)
    assert_match(/consolante/, @tournament.structure_summary)
  end

  # ── Carte d'un joueur exempt ────────────────────────────────────────────────

  # Un effectif impair met un joueur au repos à chaque journée. Sa carte doit rester
  # une carte de rencontre — même gabarit, même alignement — et ne se distinguer que
  # par le pointillé et le badge « Exempt ». Elle ne porte donc PAS le halo vert du
  # vainqueur : un exempt n'a rien gagné, il n'a pas joué. C'est ce halo, sur une
  # ligne pleine largeur, qui avait imposé de recentrer la carte et l'avait rendue
  # visuellement étrangère à ses voisines.
  test "la carte d'un joueur exempt garde le gabarit d'une carte de rencontre" do
    odd = Tournament.create!(name: "Critérium impair", sport: @sport, user: @owner,
                             format: "criterium_federal", status: "in_progress", max_players: 17,
                             players_per_pool: 3, final_phase_mode: "standard",
                             date: Date.tomorrow, place: "Salle test")
    17.times do |i|
      user = create_test_user(email: "odd#{i}@example.com")
      odd.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    odd.tournament_users.players.approved.order(:id).each_with_index { |tu, i| tu.update_column(:draw_order, i) }

    # Jusqu'aux barrages : c'est là que la carte d'un exempt est visible. En phase de
    # poules, le bye n'est pas affiché du tout (TournamentsHelper#pool_matches les
    # écarte) — 6 poules dont une de 2, donc un 2e sans 3e à affronter, qui monte au
    # tableau final d'office.
    TournamentEngine.for(odd).next_round!
    20.times do
      break if odd.barrage_rounds.exists?

      TournamentMatch.joins(:tournament_round)
                     .where(tournament_rounds: { tournament_id: odd.id })
                     .where(status: "pending", is_bye: false)
                     .to_a
                     .each { |match| win_tournament_match!(match, match.player_a) }
      TournamentEngine.for(odd).next_round!
    end

    bye = odd.barrage_rounds.first.tournament_matches.find_by(is_bye: true)
    assert bye, "la poule de 2 doit produire un exempt au tour de barrages"

    sign_in @owner
    get tournament_path(odd)
    assert_response :success

    assert_select ".tmatch-card--bye .tmatch-card__bye-badge", text: "Exempt (qualifié d'office)"
    assert_select ".tmatch-card--bye .tmatch-card__player--winner", { count: 0 },
                  "un exempt n'est pas un vainqueur : pas de halo vert, donc pas d'aplat pleine largeur"
    # Le créneau reste réservé aux vraies rencontres (rien à planifier pour un exempt).
    assert_select ".tmatch-card--bye .tmatch-card__when", count: 0
  end
end
