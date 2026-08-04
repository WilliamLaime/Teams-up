require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Padel test", slug: "padel-test-#{SecureRandom.hex(4)}", icon: "🎾")
  end

  def teardown
    teardown_db
  end

  def open_tournament(max_players: 2)
    Tournament.create!(name: "T", sport: @sport, format: "ronde_suisse", status: "open",
                       max_players: max_players, date: Date.tomorrow, place: "Terrain test")
  end

  def join!(tournament, tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@test.fr")
    tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  # ─── closed? / startable? ────────────────────────────────────────────────────
  test "closed? reflète le statut" do
    t = open_tournament
    refute t.closed?
    t.update!(status: "closed")
    assert t.closed?
  end

  test "startable? autorise le lancement depuis open ET closed" do
    t = open_tournament(max_players: 3) # > effectif inscrit, pour ne pas se clôturer tout seul
    join!(t, "a")
    join!(t, "b")

    assert t.startable?
    t.update!(status: "closed")
    assert t.startable?
    t.update!(status: "in_progress")
    refute t.startable?
  end

  # ─── close_registrations_if_full! ────────────────────────────────────────────
  test "close_registrations_if_full! clôture uniquement si open et complet" do
    t = open_tournament(max_players: 2)
    join!(t, "a")
    t.close_registrations_if_full!
    assert_equal "open", t.reload.status # pas encore complet

    join!(t, "b")
    t.close_registrations_if_full!
    assert_equal "closed", t.reload.status
  end

  test "l'inscription qui rend le tournoi complet le clôture automatiquement (callback)" do
    t = open_tournament(max_players: 2)
    join!(t, "a")
    assert t.reload.open?

    join!(t, "b")
    assert t.reload.closed?
  end

  test "close_registrations_if_full! ne rouvre pas un tournoi déjà lancé" do
    t = open_tournament(max_players: 2)
    join!(t, "a")
    join!(t, "b")
    t.update!(status: "in_progress")

    t.close_registrations_if_full!
    assert_equal "in_progress", t.reload.status
  end

  # ─── preset_capacity? ────────────────────────────────────────────────────────
  test "preset_capacity? distingue un preset (8/16/32) d'une saisie Libre" do
    assert open_tournament(max_players: 8).preset_capacity?
    assert open_tournament(max_players: 16).preset_capacity?
    refute open_tournament(max_players: 20).preset_capacity?
  end

  # ─── Réglages de structure personnalisables (Lot 7) ─────────────────────────
  # Chaque réglage vide = valeur recommandée (comportement historique).
  test "valeurs recommandées quand aucun réglage n'est saisi" do
    t = open_tournament(max_players: 8)
    assert_equal Tournament::DEFAULT_POOL_SIZE, t.pool_size
    assert_equal TournamentUser::WINS_TO_QUALIFY, t.wins_to_qualify
    assert_equal TournamentUser::LOSSES_TO_ELIMINATE, t.losses_to_eliminate
    assert_equal 4, t.planned_final_size, "≤ 8 joueurs en ronde suisse → Final 4"
  end

  test "les réglages saisis prennent le pas sur les recommandations" do
    t = open_tournament(max_players: 16)
    t.update!(players_per_pool: 3, bracket_size: 16, swiss_wins_to_qualify: 2, swiss_losses_to_eliminate: 1)

    assert_equal 3, t.pool_size
    assert_equal 2, t.wins_to_qualify
    assert_equal 1, t.losses_to_eliminate
    assert_equal 16, t.final_size
    assert_equal 16, t.planned_final_size
  end

  test "pool_count et final_size suivent la taille de poule choisie" do
    t = open_tournament(max_players: 12)
    t.update!(format: "poules")
    3.times { |i| join!(t, "p#{i}") } # 3 inscrits… mais 12 attendus

    assert_equal 3, t.planned_pool_count, "12 joueurs attendus / poules de 4"
    # 3 poules → 6 qualifiés, arrondis au tableau à 8 (2 byes) : une phase finale
    # ne peut compter que 2, 4, 8, 16… places.
    assert_equal 8, t.planned_final_size

    t.update!(players_per_pool: 6)
    assert_equal 2, t.planned_pool_count
    assert_equal 4, t.planned_final_size
  end

  test "bracket_size doit être une puissance de 2" do
    t = open_tournament(max_players: 8)
    t.bracket_size = 6
    refute t.valid?
    assert(t.errors[:bracket_size].any? { |m| m.include?("puissance de 2") })

    t.bracket_size = 8
    assert t.valid?
  end

  test "réglages de structure invalides refusés" do
    t = open_tournament(max_players: 8)
    t.players_per_pool = 1 # une poule se joue à 2 minimum
    refute t.valid?

    t.players_per_pool = nil
    t.swiss_wins_to_qualify = 0 # il faut au moins 1 victoire pour se qualifier
    refute t.valid?
  end

  # Les seuils du tournoi pilotent l'état suisse (SwissPairing#state_for les
  # transmet à TournamentUser.state_for à chaque recompute).
  test "state_for suit les seuils passés" do
    assert_equal "active", TournamentUser.state_for(2, 2)
    assert_equal "qualified", TournamentUser.state_for(3, 0)
    assert_equal "eliminated", TournamentUser.state_for(0, 3)

    # Tournoi express : 2 victoires suffisent, 1 défaite élimine.
    assert_equal "qualified", TournamentUser.state_for(2, 0, wins_to_qualify: 2, losses_to_eliminate: 1)
    assert_equal "eliminated", TournamentUser.state_for(0, 1, wins_to_qualify: 2, losses_to_eliminate: 1)
    assert_equal "active", TournamentUser.state_for(1, 0, wins_to_qualify: 2, losses_to_eliminate: 1)
  end

  # ─── structure_summary ──────────────────────────────────────────────────────
  test "structure_summary reflète le format et les réglages" do
    t = open_tournament(max_players: 16)
    assert_equal "Ronde suisse (3 V / 3 D) + quarts", t.structure_summary

    t.update!(swiss_wins_to_qualify: 2, bracket_size: 4)
    assert_equal "Ronde suisse (2 V / 3 D) + demi-finales", t.structure_summary

    t.update!(format: "poules", swiss_wins_to_qualify: nil, bracket_size: nil)
    assert_equal "4 poules de 4 + quarts", t.structure_summary

    t.update!(players_per_pool: 8)
    assert_equal "2 poules de 8 + demi-finales", t.structure_summary
  end

  test "structure_summary du championnat mentionne les playoffs" do
    t = open_tournament(max_players: 8)
    t.update!(format: "championnat", playoffs: true)
    assert_equal "8 joueurs, 7 journées, top 4 en playoffs", t.structure_summary

    t.update!(playoffs: false)
    assert_equal "8 joueurs, 7 journées, vainqueur = 1er du classement", t.structure_summary
  end
end
