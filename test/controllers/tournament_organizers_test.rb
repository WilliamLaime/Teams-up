require "test_helper"

# ── Composition de l'équipe organisatrice ─────────────────────────────────────
# Après création, l'admin doit pouvoir nommer/révoquer des co-organisateurs et
# transmettre l'administration. Quatre choses doivent tenir :
#   • seul l'ADMIN compose l'équipe (un co-organisateur ne peut pas coopter, ni
#     révoquer celui qui l'a nommé — sinon l'admin perd son tournoi) ;
#   • l'index unique [tournament_id, user_id] est respecté : promouvoir un joueur
#     inscrit met à jour SA ligne (il libère sa place), sans doublon ;
#   • un joueur d'un tournoi LANCÉ ne peut pas être promu (il a des matchs) ;
#   • le transfert échange bien les rôles (nouvel admin ↔ ancien co-organisateur).
class TournamentOrganizersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin   = create_test_user(email: "admin-org@example.com", first_name: "Alice", last_name: "Admin")
    @co_org  = create_test_user(email: "coorg-org@example.com", first_name: "Bob", last_name: "Coorg")
    @outsider = create_test_user(email: "outsider-org@example.com", first_name: "Carl", last_name: "Dehors")
    @sport = Sport.create!(name: "Ping orga", slug: "ping-pong", icon: "🏓")
    @tournament = Tournament.create!(name: "Open organisation", sport: @sport, user: @admin,
                                    format: "ronde_suisse", status: "open", max_players: 16,
                                    date: Date.tomorrow, place: "Salle test")
  end

  teardown { teardown_db }

  # ── Nomination ──────────────────────────────────────────────────────────────

  test "l'admin nomme un co-organisateur" do
    sign_in @admin

    post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }

    assert_redirected_to edit_tournament_path(@tournament)
    tu = @tournament.tournament_users.find_by(user: @outsider)
    assert_equal "co_organisateur", tu.role
    assert_equal "approved", tu.status
    assert @tournament.reload.organizer?(@outsider)
  end

  test "un co-organisateur ne peut pas en nommer un autre" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @co_org

    post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }

    assert_response :redirect
    assert_nil @tournament.tournament_users.find_by(user: @outsider)
  end

  test "un simple visiteur connecté ne peut pas nommer de co-organisateur" do
    sign_in @outsider

    post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @co_org.invite_sgid }

    assert_response :redirect
    assert_nil @tournament.tournament_users.find_by(user: @co_org)
  end

  test "promouvoir un joueur inscrit met à jour sa ligne et libère sa place" do
    inscription = @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    sign_in @admin

    assert_no_difference -> { @tournament.tournament_users.count } do
      post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }
    end

    assert_equal "co_organisateur", inscription.reload.role
    assert_equal 0, @tournament.reload.approved_players_count
  end

  test "on ne promeut pas un joueur d'un tournoi déjà lancé" do
    inscription = @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    @tournament.update!(status: "in_progress")
    sign_in @admin

    post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }

    assert_equal "joueur", inscription.reload.role
    assert_match(/lancé/, flash[:alert])
  end

  test "nommer deux fois la même personne ne crée pas de doublon" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    assert_no_difference -> { @tournament.tournament_users.count } do
      post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @co_org.invite_sgid }
    end
    assert_match(/déjà co-organisateur/, flash[:alert])
  end

  test "un sgid invalide n'inscrit personne" do
    sign_in @admin

    assert_no_difference -> { @tournament.tournament_users.count } do
      post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: "n-importe-quoi" }
    end
    assert_match(/liste de suggestions/, flash[:alert])
  end

  # ── Révocation ──────────────────────────────────────────────────────────────

  test "l'admin révoque un co-organisateur" do
    tu = @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    delete remove_co_organizer_tournament_path(@tournament, tournament_user_id: tu.id)

    assert_redirected_to edit_tournament_path(@tournament)
    assert_nil TournamentUser.find_by(id: tu.id)
    assert_not @tournament.reload.organizer?(@co_org)
  end

  test "la révocation ne peut pas cibler un JOUEUR inscrit" do
    player = @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    sign_in @admin

    delete remove_co_organizer_tournament_path(@tournament, tournament_user_id: player.id)

    assert_not_nil TournamentUser.find_by(id: player.id)
  end

  test "la révocation ne peut pas cibler l'inscription d'un AUTRE tournoi" do
    other = Tournament.create!(name: "Autre tournoi", sport: @sport, user: @admin,
                               format: "ronde_suisse", status: "open", max_players: 8,
                               date: Date.tomorrow, place: "Ailleurs")
    foreign = other.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    delete remove_co_organizer_tournament_path(@tournament, tournament_user_id: foreign.id)

    assert_not_nil TournamentUser.find_by(id: foreign.id)
  end

  # ── Transfert d'administration ──────────────────────────────────────────────

  test "le transfert échange les rôles admin et co-organisateur" do
    tu = @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    patch transfer_ownership_tournament_path(@tournament), params: { new_admin_sgid: @co_org.invite_sgid }

    assert_redirected_to tournament_path(@tournament)
    @tournament.reload
    assert_equal @co_org, @tournament.user
    # L'ancienne ligne co-org du nouvel admin est supprimée (le rôle admin est
    # porté par tournaments.user_id), l'ancien admin en reçoit une.
    assert_nil TournamentUser.find_by(id: tu.id)
    assert_equal "co_organisateur", @tournament.tournament_users.find_by(user: @admin).role
    assert @tournament.organizer?(@admin)
  end

  test "un admin inscrit comme joueur garde sa place plutôt qu'une ligne co-organisateur" do
    @tournament.tournament_users.create!(user: @admin, role: "joueur", status: "approved")
    sign_in @admin

    patch transfer_ownership_tournament_path(@tournament), params: { new_admin_sgid: @co_org.invite_sgid }

    @tournament.reload
    assert_equal @co_org, @tournament.user
    assert_equal "joueur", @tournament.tournament_users.find_by(user: @admin).role
  end

  test "un co-organisateur ne peut pas transmettre l'administration" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @co_org

    patch transfer_ownership_tournament_path(@tournament), params: { new_admin_sgid: @co_org.invite_sgid }

    assert_equal @admin, @tournament.reload.user
  end

  test "pas de transfert sur un tournoi terminé" do
    @tournament.update!(status: "completed")
    sign_in @admin

    patch transfer_ownership_tournament_path(@tournament), params: { new_admin_sgid: @co_org.invite_sgid }

    assert_equal @admin, @tournament.reload.user
  end

  # ── Autocomplete ────────────────────────────────────────────────────────────

  test "l'autocomplete masque les personnes déjà à l'organisation" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    get search_tournaments_path(q: "Coorg", tournament_id: @tournament.to_param)

    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  # ── Affichage ───────────────────────────────────────────────────────────────

  test "le panneau n'apparaît que pour l'admin" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")

    sign_in @admin
    get edit_tournament_path(@tournament)
    assert_select "form[action=?]", add_co_organizer_tournament_path(@tournament), 1

    sign_out @admin
    sign_in @co_org
    get edit_tournament_path(@tournament)
    assert_response :success
    assert_select "form[action=?]", add_co_organizer_tournament_path(@tournament), 0
  end

  # La vue d'ensemble n'affichait que l'admin : un tournoi géré à plusieurs y
  # paraissait tenu par une seule personne, alors que l'onglet Participants les
  # listait déjà tous.
  test "la vue d'ensemble liste l'admin ET les co-organisateurs" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")

    get tournament_path(@tournament)

    assert_response :success
    assert_select ".tournament-overview__item dt", text: /Organisateurs/
    assert_select ".tournament-overview__item dd", text: /#{@admin.display_name}/
    assert_select ".tournament-overview__item dd", text: /#{@co_org.display_name}/
  end

  # Sans co-organisateur, préciser « (admin) » n'apporte rien : il n'y a personne
  # dont se distinguer, et le libellé reste au singulier.
  test "la vue d'ensemble reste au singulier sans co-organisateur" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select ".tournament-overview__item dt", text: /Organisateur/
    assert_select ".tournament-overview__item dt", text: /Organisateurs/, count: 0
    assert_select ".tournament-overview__role", count: 0
  end
end
