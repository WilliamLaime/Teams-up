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
end
