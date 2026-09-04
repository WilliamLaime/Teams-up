# Tests d'intégration pour TournamentMatchesController (Lot 4).
# Saisie du score set-par-set (vainqueur dérivé), droits (organisateur + joueurs),
# verrouillage du tour, génération auto de la ronde suivante.
require "test_helper"

class TournamentMatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin  = create_test_user(email: "admin@example.com")
    @lambda = create_test_user(email: "lambda@example.com")
    @sport  = Sport.create!(name: "Tennis Test", slug: "tennis", icon: "🎾")

    @tournament = Tournament.create!(name: "T", sport: @sport, user: @admin,
                                     format: "ronde_suisse", status: "open", max_players: 8,
                                     date: Date.tomorrow, place: "Terrain test")
    8.times do |i|
      u = create_test_user(email: "j#{i}@example.com")
      @tournament.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    SwissPairing.new(@tournament).next_round! # génère la ronde 1
    @match = @tournament.current_round.tournament_matches.where(is_bye: false).first
  end

  teardown { teardown_db }

  # Score « sec » pour player_a (2 sets à 6-0), conforme au tennis.
  def straight_win = { tournament_match: { games_a: [6, 6], games_b: [0, 0] } }

  # ── Créneau de la rencontre planifiée ───────────────────────────────────────
  # La date ne vit pas sur le TournamentMatch : elle arrive avec la rencontre
  # (Match) que les joueurs créent pour convenir de leur créneau. Sans cet
  # affichage, il fallait ouvrir chaque rencontre pour savoir quand on joue.
  def schedule_match!(date:, time:)
    Match.create!(title: "Rencontre de tournoi", date: date, time: time,
                  players_needed: 2, level: "Débutant", visibility: "public",
                  validation_mode: "automatic", genre_restriction: "tous",
                  user: @admin, sport: @sport,
                  tournament: @tournament, tournament_match: @match)
  end

  test "la carte affiche le créneau de la rencontre planifiée" do
    schedule_match!(date: Date.tomorrow, time: Time.current.change(hour: 19, min: 0))

    # Le board ne montre les cartes qu'une fois le tournoi lancé : tant qu'il est
    # `open`, c'est le panneau de lancement qui occupe l'onglet Matchs.
    @tournament.update!(status: "in_progress")
    get tournament_path(@tournament)

    assert_response :success
    # Date ABSOLUE, jamais « Demain » : un tournoi s'étale sur plusieurs semaines,
    # et deux journées différentes portaient sinon le même libellé.
    attendu = "#{I18n.l(Date.tomorrow, format: '%A %-d %b')} 19h"
    assert_select ".tmatch-card__when", text: /#{Regexp.escape(attendu)}/
  end

  # ── Forfait : V / D sur la carte ────────────────────────────────────────────
  # Un forfait n'a AUCUN set saisi : la carte tombait donc dans la branche « pas
  # encore joué » et n'affichait qu'un tiret, alors que le classement de la poule
  # était déjà recalculé. Le vainqueur apprenait sa victoire ailleurs que sur la
  # carte de son propre match.
  test "la carte d'un match par forfait affiche V et D" do
    @match.update!(forfeit: true, retired_player: @match.player_b)
    @tournament.update!(status: "in_progress")

    get tournament_path(@tournament)

    assert_response :success
    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark.is-winner", text: "V"
    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark.is-loser",  text: "D"
  end

  # Sur un match joué, le score en vert désigne déjà le vainqueur : pas de marque.
  test "la carte d'un match joué n'affiche aucune marque de forfait" do
    @tournament.update!(status: "in_progress")
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    get tournament_path(@tournament)

    assert_select "#tmatch_#{@match.id} .tmatch-card__forfeit-mark", count: 0
  end

  # ── Bulle de discussion ─────────────────────────────────────────────────────
  # Le fil est privé à la confrontation, et la bulle est le SEUL moyen de le
  # trouver : si elle fuit vers un tiers, le fil fuit avec elle.
  test "la bulle de chat n'est visible que des joueurs du match et des organisateurs" do
    @tournament.update!(status: "in_progress")
    autre_joueur = @tournament.tournament_users.where.not(id: [@match.player_a_id, @match.player_b_id]).first

    { @match.player_a.user => 1, @admin => 1, autre_joueur.user => 0, @lambda => 0 }.each do |user, attendu|
      sign_in user
      get tournament_path(@tournament)
      assert_select "#tmatch_#{@match.id} .tmatch-card__chat-btn", { count: attendu },
                    "bulle attendue #{attendu} fois pour #{user.email}"
      sign_out user
    end
  end

  # La pastille est le seul signal de non-lu de ce chat (il n'apparaît ni dans la
  # sidebar globale, ni en notification) : sans elle, un message passe inaperçu.
  test "la pastille non-lu s'allume puis s'éteint une fois le fil ouvert" do
    @tournament.update!(status: "in_progress")
    Message.create!(user: @match.player_b.user, tournament_match: @match, content: "Jeudi 17h45 ?")

    sign_in @match.player_a.user
    get tournament_path(@tournament)
    assert_select "#tmatch_#{@match.id} .tmatch-card__chat-dot", count: 1

    get tournament_match_conversation_path(@match)
    get tournament_path(@tournament)
    assert_select "#tmatch_#{@match.id} .tmatch-card__chat-dot", count: 0
  end

  # Mon propre message ne doit jamais allumer ma propre pastille.
  test "la pastille ignore mes propres messages" do
    @tournament.update!(status: "in_progress")
    Message.create!(user: @match.player_a.user, tournament_match: @match, content: "Jeudi 17h45 ?")

    sign_in @match.player_a.user
    get tournament_path(@tournament)

    assert_select "#tmatch_#{@match.id} .tmatch-card__chat-dot", count: 0
  end

  # Une rencontre peut exister sans date (colonne nullable). Le bandeau reste
  # AFFICHÉ et annonce « Date à définir » : c'est lui qui aligne les cartes entre
  # elles, un bandeau conditionnel décalerait tout ce qui le suit d'une carte à
  # l'autre dans une même rangée (cf. _tmatch_when.html.erb).
  test "le créneau annonce « Date à définir » quand la rencontre n'a pas de date" do
    match = schedule_match!(date: Date.tomorrow, time: nil)
    match.update_columns(date: nil)

    # Le board ne montre les cartes qu'une fois le tournoi lancé : tant qu'il est
    # `open`, c'est le panneau de lancement qui occupe l'onglet Matchs.
    @tournament.update!(status: "in_progress")
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".tmatch-card__when.tmatch-card__when--tbd", text: /Date à définir/
    assert_select "a", text: "Voir la rencontre"
  end

  test "l'organisateur enregistre un score, le vainqueur est dérivé" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    @match.reload
    assert_equal @match.player_a_id, @match.winner_id
    assert_equal "completed", @match.status
    assert_equal [[6, 0], [6, 0]], @match.sets
  end

  test "un joueur du match peut saisir le score" do
    sign_in @match.player_a.user
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    assert_equal @match.player_a_id, @match.reload.winner_id
  end

  test "réponse Turbo Stream : le board est remplacé (le partial compile)" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win, as: :turbo_stream

    assert_response :success
    assert_match "tournament_board", response.body
  end

  test "un tiers (ni organisateur ni joueur) est refusé" do
    sign_in @lambda
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    assert_response :redirect
    assert_nil @match.reload.winner_id
  end

  test "ronde terminée → génération automatique de la ronde suivante" do
    sign_in @admin
    pending = @tournament.current_round.tournament_matches.where(status: "pending", is_bye: false).to_a
    pending[0..-2].each { |m| win_tournament_match!(m, m.player_a) }
    last = pending.last

    assert_difference -> { @tournament.tournament_rounds.count }, 1 do
      patch tournament_tournament_match_path(@tournament, last), params: straight_win
    end
  end

  test "tour verrouillé : re-saisir un match d'une ronde close est refusé et ne double pas les rondes" do
    sign_in @admin
    @tournament.current_round.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(@tournament).next_round! # clôt la ronde 1, en crée une 2e
    rounds_before = @tournament.tournament_rounds.count

    patch tournament_tournament_match_path(@tournament, @match.reload), params: straight_win
    assert_response :redirect
    assert_equal rounds_before, @tournament.reload.tournament_rounds.count
  end

  # ── Correction de score après verrouillage (Lot 5) ────────────────────────────
  # Le score « inversé » : player_b gagne (2 sets à 6-0 côté B).
  def straight_win_b = { tournament_match: { games_a: [0, 0], games_b: [6, 6] } }

  test "l'organisateur corrige un score d'un tour verrouillé (contourne le verrou)" do
    sign_in @admin
    @tournament.current_round.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(@tournament).next_round! # verrouille la ronde 1
    assert_equal "completed", @match.reload.tournament_round.status

    loser = @match.player_b
    patch correct_tournament_tournament_match_path(@tournament, @match), params: straight_win_b
    assert_equal loser.id, @match.reload.winner_id, "le vainqueur doit être corrigé"
  end

  test "correction qui change le vainqueur régénère l'aval (ronde suivante)" do
    sign_in @admin
    @tournament.current_round.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(@tournament).next_round!
    old_round2_id = @tournament.swiss_rounds.last.id

    patch correct_tournament_tournament_match_path(@tournament, @match.reload), params: straight_win_b

    new_round2 = @tournament.reload.swiss_rounds.last
    assert_not_equal old_round2_id, new_round2.id, "la ronde suivante doit être détruite puis régénérée"
    assert_equal 2, @tournament.swiss_rounds.count, "on ne double pas les rondes"
  end

  test "un tiers ne peut pas corriger un score" do
    sign_in @lambda
    @tournament.current_round.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(@tournament).next_round!
    original = @match.reload.winner_id

    patch correct_tournament_tournament_match_path(@tournament, @match), params: straight_win_b
    assert_response :redirect
    assert_equal original, @match.reload.winner_id
  end
end
