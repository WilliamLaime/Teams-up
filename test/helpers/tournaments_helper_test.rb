require "test_helper"

# Tests du module TournamentsHelper, côté CALENDRIER et PLACEHOLDERS de tableau.
#
# Ce qui est couvert ici a un point commun : ce sont des règles de dérivation
# qu'aucune colonne ne porte, et qu'une vue ne peut donc pas « vérifier » d'un
# coup d'œil —
#   • calendar_matches      : quelles rencontres ont une place dans une grille ;
#   • calendar_context_label: poule ou tour, selon la phase ;
#   • tournament_hour       : la convention d'heure du projet (« 19h ») ;
#   • bracket_feeder_label  : d'où viendra l'occupant d'une case vide ;
#   • bracket_seed_labels   : les têtes de série attendues au premier tour.
class TournamentsHelperTest < ActionView::TestCase
  include TournamentsHelper

  parallelize(workers: 1)

  setup do
    @admin = create_test_user(email: "admin-tcal@example.com")
    @sport = Sport.create!(name: "Tennis Cal", slug: "tennis-cal", icon: "🎾")

    @tournament = Tournament.create!(name: "Tournoi calendrier", sport: @sport, user: @admin,
                                     format: "ronde_suisse", status: "in_progress", max_players: 8,
                                     date: Date.current + 30, place: "Terrain test")

    @players = 4.times.map do |i|
      user = create_test_user(email: "cal#{i}@example.com")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end

    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1, branch: "main")
  end

  teardown { teardown_db }

  # ─── Helpers de fabrication ─────────────────────────────────────────────────

  def tmatch!(position:, is_bye: false, round: @round, player_b: @players[1])
    TournamentMatch.create!(tournament_round: round, position: position, is_bye: is_bye,
                            player_a: @players[0], player_b: is_bye ? nil : player_b)
  end

  # `validate: false` : le modèle Match refuse une date passée à la création, or
  # un calendrier doit précisément savoir afficher les rencontres déjà jouées.
  def schedule!(tmatch, date:, time: "19:00")
    match = Match.new(title: "Rencontre", date: date, time: Time.zone.parse(time),
                      players_needed: 2, level: "Débutant", visibility: "public",
                      validation_mode: "automatic", genre_restriction: "tous",
                      user: @admin, sport: @sport,
                      tournament: @tournament, tournament_match: tmatch)
    match.save!(validate: false)
    match
  end

  # ─── calendar_matches ───────────────────────────────────────────────────────

  test "calendar_matches ne retient que les rencontres datées" do
    datee    = tmatch!(position: 0)
    sans_date = tmatch!(position: 1, player_b: @players[2])
    sans_rencontre = tmatch!(position: 2, player_b: @players[3])

    schedule!(datee, date: Date.current + 3)
    # Rencontre créée mais créneau pas encore convenu : la colonne est nullable.
    schedule!(sans_date, date: Date.current + 1).update_columns(date: nil)

    resultat = calendar_matches(@tournament)

    assert_equal [datee.id], resultat.map(&:id)
    assert_not_includes resultat.map(&:id), sans_date.id
    assert_not_includes resultat.map(&:id), sans_rencontre.id
  end

  test "calendar_matches exclut les byes" do
    bye = tmatch!(position: 0, is_bye: true)
    schedule!(bye, date: Date.current + 2)

    assert_empty calendar_matches(@tournament)
  end

  test "calendar_matches trie par date puis par heure" do
    tard  = tmatch!(position: 0)
    tot   = tmatch!(position: 1, player_b: @players[2])
    veille = tmatch!(position: 2, player_b: @players[3])

    schedule!(tard,   date: Date.current + 5, time: "20:30")
    schedule!(tot,    date: Date.current + 5, time: "09:00")
    schedule!(veille, date: Date.current + 4, time: "23:00")

    assert_equal [veille.id, tot.id, tard.id], calendar_matches(@tournament).map(&:id)
  end

  # ─── calendar_context_label ─────────────────────────────────────────────────

  test "calendar_context_label nomme le tour hors phase de poules" do
    assert_equal "Ronde 1", calendar_context_label(tmatch!(position: 0), [])
  end

  test "calendar_context_label nomme la poule en phase de poules" do
    poule = @tournament.tournament_rounds.create!(phase: "pool", number: 1, branch: "main")
    @players[0].update!(pool: 1)

    assert_equal "Poule B", calendar_context_label(tmatch!(position: 0, round: poule), [])
  end

  # ─── tournament_hour ────────────────────────────────────────────────────────

  test "tournament_hour applique la convention d'heure du projet" do
    tmatch = tmatch!(position: 0)

    assert_equal "19h",    tournament_hour(schedule!(tmatch, date: Date.current + 1, time: "19:00"))
    assert_equal "17h45",  tournament_hour(schedule!(tmatch!(position: 1, player_b: @players[2]),
                                                     date: Date.current + 1, time: "17:45"))
  end

  test "tournament_hour renvoie nil sans heure" do
    match = schedule!(tmatch!(position: 0), date: Date.current + 1)
    match.update_columns(time: nil)

    assert_nil tournament_hour(match.reload)
    assert_nil tournament_hour(nil)
  end

  # ─── Placeholders du tableau final ──────────────────────────────────────────

  test "bracket_feeder_label annonce le match nourricier" do
    # Tableau à 4 tours : 8es, quarts, demies, finale.
    assert_equal "Vainqueur 8e de finale 1",     bracket_feeder_label(1, 0, 4)
    assert_equal "Vainqueur quart de finale 4",  bracket_feeder_label(2, 3, 4)
    assert_equal "Vainqueur demi-finale 2",      bracket_feeder_label(3, 1, 4)
  end

  test "bracket_feeder_label se tait sur la première colonne" do
    # Ses occupants viennent de la phase qualificative : leur appariement dépend
    # du format, on ne peut pas l'annoncer sans risquer de dire faux.
    assert_nil bracket_feeder_label(0, 0, 4)
  end

  test "bracket_seed_labels suit le seeding standard 1 vs N" do
    assert_equal ["Tête de série 1", "Tête de série 16"], bracket_seed_labels(16, 0)
    assert_equal ["Tête de série 8", "Tête de série 9"],  bracket_seed_labels(16, 1)
  end

  # ─── tournament_match_schedule ──────────────────────────────────────────────
  # Le créneau est affiché en date ABSOLUE. « Jeudi » tout court ne disait pas de
  # quel jeudi il s'agissait : sur un tournoi étalé sur plusieurs semaines, deux
  # journées différentes portaient le même libellé.

  test "tournament_match_schedule donne le jour, le quantième, le mois abrégé et l'heure" do
    tmatch = tmatch!(position: 0)
    schedule!(tmatch, date: Date.new(2026, 9, 3), time: "17:45")

    assert_equal "jeudi 3 sept. 17h45", tournament_match_schedule(tmatch.reload)
  end

  # Un match tout proche n'est PAS raccourci en « Aujourd'hui » / « Demain » :
  # toutes les cartes du tableau gardent la même forme, donc se comparent.
  test "tournament_match_schedule ne raccourcit pas les dates proches" do
    tmatch = tmatch!(position: 0)
    schedule!(tmatch, date: Date.current + 1, time: "19:00")

    resultat = tournament_match_schedule(tmatch.reload)

    assert_equal "#{I18n.l(Date.current + 1, format: '%A %-d %b')} 19h", resultat
    assert_no_match(/Demain/, resultat)
  end

  # Convention du projet conservée : « 19h », jamais « 19h00 ».
  test "tournament_match_schedule omet les minutes à l'heure pile" do
    tmatch = tmatch!(position: 0)
    schedule!(tmatch, date: Date.new(2026, 12, 14), time: "19:00")

    assert_equal "lundi 14 déc. 19h", tournament_match_schedule(tmatch.reload)
  end

  test "tournament_match_schedule se tait sans rencontre ni date" do
    sans_rencontre = tmatch!(position: 0)
    assert_nil tournament_match_schedule(sans_rencontre)

    sans_date = tmatch!(position: 1, player_b: @players[2])
    schedule!(sans_date, date: Date.current + 1).update_columns(date: nil)
    assert_nil tournament_match_schedule(sans_date.reload)
  end

  # ─── forfeit_mark ───────────────────────────────────────────────────────────
  # Un forfait n'a aucun set saisi : sans cette marque, la carte affichait le
  # tiret « pas encore joué » alors que le classement de la poule était tranché.

  test "forfeit_mark donne V au vainqueur et D au joueur forfait" do
    tmatch = tmatch!(position: 0)
    tmatch.update!(forfeit: true, retired_player: @players[1])
    tmatch.reload

    assert_equal @players[0].id, tmatch.winner_id, "le vainqueur doit être dérivé du forfait"
    assert_equal "V", forfeit_mark(tmatch, @players[0])
    assert_equal "D", forfeit_mark(tmatch, @players[1])
  end

  # Sur un match joué, le score en vert désigne déjà le vainqueur : doubler le
  # signal alourdirait la carte pour rien.
  test "forfeit_mark se tait hors forfait" do
    tmatch = tmatch!(position: 0)
    assert_nil forfeit_mark(tmatch, @players[0])

    tmatch.assign_score([[6, 4], [6, 3]])
    tmatch.save!
    assert_nil forfeit_mark(tmatch.reload, @players[0])
  end

  # forfeit sans retired_player ne désigne aucun vainqueur : on n'invente pas un
  # perdant à partir d'un drapeau incomplet.
  test "forfeit_mark se tait quand aucun vainqueur n'est désigné" do
    tmatch = tmatch!(position: 0)
    tmatch.update_columns(forfeit: true)

    assert_nil tmatch.reload.winner_id
    assert_nil forfeit_mark(tmatch, @players[0])
  end

  test "forfeit_mark_tag rend une marque accessible" do
    tmatch = tmatch!(position: 0)
    tmatch.update!(forfeit: true, retired_player: @players[1])

    gagnant = forfeit_mark_tag(tmatch.reload, @players[0])
    perdant = forfeit_mark_tag(tmatch, @players[1])

    assert_includes gagnant, "is-winner"
    assert_includes gagnant, "Victoire par forfait"
    assert_includes perdant, "is-loser"
    assert_includes perdant, "Défaite par forfait"
    assert_nil forfeit_mark_tag(tmatch, nil)
  end
end
