require "test_helper"

# Rendu de la carte de match en variante EMPILÉE (poules) — celle qu'un joueur
# voit le plus souvent, et la seule où le score forme une colonne à droite.
#
# Le test de TournamentMatchesControllerTest couvre la scoreline CENTRÉE (ronde
# suisse) : les deux mises en page passent par des branches distinctes de
# _tmatch_scoreline, une seule des deux vérifiée laissait l'autre sans filet.
class TournamentPoolCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @admin = create_test_user(email: "pool-admin@example.com")
    @sport = Sport.create!(name: "Ping Pool", slug: "ping-pool", icon: "🏓")
    @tournament = Tournament.create!(name: "T poules", sport: @sport, user: @admin, format: "poules",
                                     status: "open", max_players: 8, date: Date.tomorrow, place: "Gymnase")
    8.times do |i|
      @tournament.tournament_users.create!(user: create_test_user(email: "pp#{i}@example.com"),
                                           role: "joueur", status: "approved")
    end
    TournamentEngine.for(@tournament).next_round!

    @match = TournamentMatch.joins(:tournament_round)
                            .where(tournament_rounds: { tournament_id: @tournament.id }, is_bye: false)
                            .first

    # Un tournoi de 8 joueurs dont la 1re journée est générée se referme aussitôt
    # dans ce montage minimal ; le tableau n'affiche ses cartes qu'en cours.
    @tournament.update_columns(status: "in_progress")
  end

  # « F » et non « D » pour le joueur qui a déclaré forfait : il ne s'est pas
  # présenté, il n'a pas perdu au score. Le « D » reste réservé au forfait dont
  # aucun partant n'est identifié (cf. TournamentsHelper#forfeit_mark).
  test "un forfait affiche V au vainqueur et F au joueur forfait" do
    @match.update!(forfeit: true, retired_player: @match.player_b)

    sign_in @match.player_a.user
    get tournament_path(@tournament)

    assert_response :success
    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark.is-winner",  text: "V"
    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark.is-forfeit", text: "F"
    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark.is-loser",   count: 0
    # Le tiret « pas encore joué » ne doit plus cohabiter avec le résultat.
    assert_select "#tmatch_#{@match.id} .tmatch-card__row-score--pending", count: 0
  end

  test "un match à venir garde ses tirets et aucune marque de forfait" do
    sign_in @match.player_a.user
    get tournament_path(@tournament)

    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark", count: 0
    assert_select "#tmatch_#{@match.id} .tmatch-card__row-score--pending", count: 2
  end

  test "la bulle de chat est réservée aux joueurs du match et aux organisateurs" do
    tiers = @tournament.tournament_users
                       .where.not(id: [@match.player_a_id, @match.player_b_id]).first

    { @match.player_a.user => 1, @admin => 1, tiers.user => 0 }.each do |user, attendu|
      sign_in user
      get tournament_path(@tournament)
      assert_select "#tmatch_#{@match.id} .tmatch-card__chat-btn", { count: attendu },
                    "bulle attendue #{attendu} fois pour #{user.email}"
      sign_out user
    end
  end
end
