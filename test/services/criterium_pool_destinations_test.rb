require "test_helper"

# ── Tests du zonage vert/orange/rouge des tables de poule (Critérium) ─────────
# Une table de poule annonce où chaque position va en phase finale : liseré vert
# = tableau final, orange = barrages, rouge = consolante. Deux sources selon le
# moment, et c'est tout l'objet de ce fichier :
#   - poules en cours → PRÉDICTION par le rang (TournamentsHelper#pool_destinations) ;
#   - barrages tirés  → FAIT lu dans les matchs (Tournament#pool_exit_destinations).
# Le zonage doit survivre à cette bascule : c'est précisément ce qui manquait,
# le liseré disparaissait au tirage des barrages.
class CriteriumPoolDestinationsTest < ActiveSupport::TestCase
  include TournamentsHelper

  def setup
    @sport = Sport.create!(name: "Ping test", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # `final_phase_mode` explicite : les seuils d'effectif basculent 16 joueurs ou
  # moins en classement intégral (tableau unique). Les tests qui veulent des
  # barrages doivent donc demander "standard", sinon ils testent autre chose.
  def build_tournament(count, players_per_pool: 4, final_phase_mode: "standard")
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "criterium_federal", status: "open", max_players: count,
                                    players_per_pool: players_per_pool,
                                    final_phase_mode: final_phase_mode,
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    # Le tirage au sort du lancement : `draw_order` est la seule source d'aléa des
    # moteurs, sans lui les poules ne sont pas reproductibles.
    tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    tournament
  end

  def resolve_all_pending!(tournament)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, match.player_a) }
  end

  # Le lancement, comme TournamentsController#start : le statut fait partie du
  # lancement, et `show_pool_destinations?` le lit (in_progress / completed).
  def start!(tournament)
    tournament.update!(status: "in_progress")
    TournamentEngine.for(tournament).next_round!
    tournament
  end

  # Joue les poules jusqu'à l'apparition des barrages.
  def play_pools!(tournament)
    start!(tournament)
    20.times do
      break if tournament.barrage_rounds.exists?

      resolve_all_pending!(tournament)
      TournamentEngine.for(tournament).next_round!
    end
    Tournament.find(tournament.id)
  end

  # Le helper mémoïse par instance (@pool_destinations) : chaque assertion repart
  # d'un état propre pour ne pas lire la réponse d'un tournoi précédent.
  def reset_helper_memo = @pool_destinations = nil

  # ── Avant le tirage : la prédiction par rang ────────────────────────────────

  test "poules en cours : la destination est prédite par le rang de poule" do
    tournament = start!(build_tournament(16))
    reset_helper_memo

    assert_equal({ 1 => :bracket, 2 => :barrage, 3 => :barrage, 4 => :consolation },
                 pool_destinations(tournament).sort.to_h)

    tournament = Tournament.find(tournament.id)

    tournament.ranked_pools.each_value do |players|
      assert_equal [:bracket, :barrage, :barrage, :consolation],
                   players.map { |tu| pool_destination_for(tournament, tu) }
    end
  end

  # ── Après le tirage : le parcours réel ──────────────────────────────────────

  test "barrages tirés : la destination est lue dans les matchs joués" do
    tournament = play_pools!(build_tournament(16))
    reset_helper_memo

    assert tournament.final_phase_started?, "les barrages doivent exister"

    # Au tirage, SEULS les barrages ont des matchs : le tableau final et la
    # consolante n'accueillent leurs entrants qu'après. Le modèle ne prétend donc
    # rien savoir des 8 autres joueurs — 4 poules de 4 → 8 joueurs aux barrages.
    destinations = tournament.pool_exit_destinations
    assert_equal 8, destinations.size
    assert_equal [:barrage], destinations.values.uniq

    # …et c'est le helper qui garde le zonage complet, en repliant sur le rang
    # pour les portes encore fermées : 16 lignes, 16 couleurs, aucune blanche.
    tournament.ranked_pools.each_value do |players|
      assert_equal [:bracket, :barrage, :barrage, :consolation],
                   players.map { |tu| pool_destination_for(tournament, tu) }
    end
  end

  test "un vainqueur de barrage reste orange : il est sorti des poules par les barrages" do
    tournament = play_pools!(build_tournament(16))
    resolve_all_pending!(tournament)          # les barrages sont joués
    TournamentEngine.for(tournament).next_round!  # le tableau final est construit
    tournament = Tournament.find(tournament.id)

    barrage_players = tournament.barrage_rounds.flat_map do |round|
      round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    end
    assert_predicate barrage_players, :any?
    assert tournament.tournament_rounds.bracket.exists?, "le tableau final doit exister"

    destinations = tournament.pool_exit_destinations
    # Le vainqueur joue ENSUITE le tableau final : sans la priorité du barrage, sa
    # ligne repasserait au vert et le zonage orange s'effondrerait.
    barrage_players.each do |player_id|
      assert_equal :barrage, destinations[player_id]
    end
  end

  test "tableaux construits : les trois portes sont connues pour tout le monde" do
    tournament = play_pools!(build_tournament(16))
    resolve_all_pending!(tournament)              # barrages joués
    TournamentEngine.for(tournament).next_round!  # tableau final + consolante
    tournament = Tournament.find(tournament.id)
    reset_helper_memo

    destinations = tournament.pool_exit_destinations
    counts = destinations.values.tally

    # L'invariant « aucun joueur perdu, aucun en double » : 4 premiers de poule au
    # tableau final, 8 (2es + 3es) aux barrages, 4 quatrièmes en consolante.
    assert_equal 16, destinations.size
    assert_equal 4, counts[:bracket]
    assert_equal 8, counts[:barrage]
    assert_equal 4, counts[:consolation]

    # Le zonage est alors intégralement factuel, et toujours contigu par rang.
    tournament.ranked_pools.each_value do |players|
      assert_equal [:bracket, :barrage, :barrage, :consolation],
                   players.map { |tu| pool_destination_for(tournament, tu) }
    end
  end

  # ── L'affichage : le zonage survit au tirage ────────────────────────────────

  test "le zonage reste affiché après le tirage des barrages" do
    tournament = play_pools!(build_tournament(16))
    reset_helper_memo

    assert tournament.final_phase_started?
    assert show_pool_destinations?(tournament),
           "le liseré doit survivre au tirage — c'est tout l'objet du changement"
  end

  test "le zonage reste affiché sur un tournoi terminé" do
    tournament = play_pools!(build_tournament(16))
    tournament.update!(status: "completed")
    reset_helper_memo

    assert show_pool_destinations?(tournament)
  end

  test "aucun zonage en mode intégral : tout le monde va au tableau final" do
    tournament = start!(build_tournament(12, final_phase_mode: "integral"))
    reset_helper_memo

    assert_equal [:bracket], pool_destinations(tournament).values.uniq
    assert_not show_pool_destinations?(tournament),
               "un liseré vert partout n'informe de rien"
  end

  # ── Les libellés ────────────────────────────────────────────────────────────

  test "le libellé d'une destination suit le temps grammatical" do
    assert_equal "Va au tableau final", destination_label(:bracket)
    assert_equal "Au tableau final",    destination_label(:bracket, predicted: false)
    assert_equal "Passe par les barrages", destination_label(:barrage)
    assert_equal "Passé par les barrages", destination_label(:barrage, predicted: false)
    assert_equal "Descend en consolante",  destination_label(:consolation)
    assert_equal "Descendu en consolante", destination_label(:consolation, predicted: false)
    assert_equal "trophy", destination_icon(:bracket)
  end
end
