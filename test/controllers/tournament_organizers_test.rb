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

  test "nommer un joueur inscrit lui donne les droits SANS lui prendre sa place" do
    inscription = @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    sign_in @admin

    assert_no_difference -> { @tournament.tournament_users.count } do
      post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }
    end

    # Le rôle ne bouge pas : il dit « occupe une place », pas « a les droits ».
    assert_equal "joueur", inscription.reload.role
    assert_predicate inscription, :co_organizer?
    assert_equal 1, @tournament.reload.approved_players_count
    assert @tournament.organizer?(@outsider)
  end

  test "on peut nommer un joueur même une fois le tournoi lancé" do
    inscription = @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    @tournament.update!(status: "in_progress")
    sign_in @admin

    post add_co_organizer_tournament_path(@tournament), params: { co_organizer_sgid: @outsider.invite_sgid }

    # Rien n'est retiré des poules ni des appariements en cours : c'est justement
    # ce que le drapeau permet, là où un changement de rôle était interdit.
    assert_equal "joueur", inscription.reload.role
    assert_predicate inscription, :co_organizer?
    assert_nil flash[:alert]
  end

  test "révoquer un co-organisateur qui joue le laisse inscrit comme joueur" do
    inscription = @tournament.tournament_users.create!(user: @outsider, role: "joueur",
                                                       status: "approved", co_organizer: true)
    sign_in @admin

    assert_no_difference -> { @tournament.tournament_users.count } do
      delete remove_co_organizer_tournament_path(@tournament, tournament_user_id: inscription.id)
    end

    assert_not_predicate inscription.reload, :co_organizer?
    assert_equal "joueur", inscription.role
    assert_not @tournament.reload.organizer?(@outsider)
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

  # Les co-organisateurs en place étaient RETIRÉS des résultats : l'admin voyait
  # « Aucun joueur trouvé », indiscernable d'une faute de frappe. Ils sont désormais
  # proposés et marqués — c'est le seul moyen de comprendre le refus depuis l'UI.
  test "l'autocomplete marque les personnes déjà à l'organisation au lieu de les masquer" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    get search_tournaments_path(q: "Coorg", tournament_id: @tournament.to_param)

    assert_response :success
    result = JSON.parse(response.body)
    assert_equal 1, result.size
    assert result.first["already_organizer"], "le co-organisateur en place doit être marqué"
  end

  # Le cas qui rendait l'incident indiagnosticable : une ligne co_organizer: true
  # avec un statut non approuvé était invisible dans le panneau (filtré .approved)
  # tout en bloquant toute nouvelle nomination.
  test "un co-organisateur non approuvé est visible dans le panneau et marqué dans l'autocomplete" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "pending")
    sign_in @admin

    assert_includes @tournament.reload.co_organizers.map(&:user), @co_org

    get search_tournaments_path(q: "Coorg", tournament_id: @tournament.to_param)
    assert result = JSON.parse(response.body).first
    assert result["already_organizer"]
  end

  # Le transfert d'administration interroge le même endpoint avec le tournoi MAIS
  # en contexte "transfer" : un co-organisateur en place doit y rester
  # sélectionnable, puisque c'est justement lui qu'on promeut.
  test "l'autocomplete de transfert ne marque personne" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    get search_tournaments_path(q: "Coorg", tournament_id: @tournament.to_param, context: "transfer")

    result = JSON.parse(response.body)
    assert_equal 1, result.size
    refute result.first["already_organizer"]
  end

  # ── Suggestions par défaut de l'autocomplete ────────────────────────────────
  # Le champ n'appelait l'endpoint qu'à partir de 3 caractères, qui répondait []
  # en dessous : le dropdown restait vide, sans aucune piste sur qui nommer.

  test "sans terme de recherche, l'autocomplete propose les inscrits puis les amis" do
    @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    Friendship.create!(user: @admin, friend: @co_org, status: "accepted")
    sign_in @admin

    get search_tournaments_path(tournament_id: @tournament.to_param)

    assert_response :success
    result = JSON.parse(response.body)
    assert_equal %w[Carl Bob], result.map { |u| u["first_name"] },
                 "les inscrits doivent précéder les amis"
    groups = result.map { |u| u["group"] }
    assert_equal ["Inscrits au tournoi", "Tes amis"], groups
  end

  # L'admin et le demandeur lui-même n'ont jamais à être proposés (cf.
  # TournamentsController#excluded_search_ids) — y compris quand ils sont inscrits.
  test "les suggestions excluent l'admin du tournoi et le demandeur" do
    @tournament.tournament_users.create!(user: @admin, role: "joueur", status: "approved")
    sign_in @admin

    get search_tournaments_path(tournament_id: @tournament.to_param)

    assert_empty JSON.parse(response.body)
  end

  # Le champ de transfert d'administration et celui de la page de création appellent
  # le même endpoint sans tournament_id : pas d'inscrits, seulement les amis.
  test "sans tournament_id, les suggestions se limitent aux amis" do
    @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    Friendship.create!(user: @co_org, friend: @admin, status: "accepted")
    sign_in @admin

    get search_tournaments_path

    result = JSON.parse(response.body)
    assert_equal ["Bob"], result.map { |u| u["first_name"] },
                 "une amitié reçue compte aussi (User#all_friends)"
    groups = result.map { |u| u["group"] }
    assert_equal ["Tes amis"], groups
  end

  # Le champ de transfert doit proposer les membres du tournoi, pas seulement les
  # amis : le nouvel admin est presque toujours quelqu'un qui est déjà dedans.
  test "en contexte transfert, les suggestions incluent les membres du tournoi" do
    @tournament.tournament_users.create!(user: @outsider, role: "joueur", status: "approved")
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    get search_tournaments_path(tournament_id: @tournament.to_param, context: "transfer")

    result = JSON.parse(response.body)
    assert_equal %w[Carl Bob].sort, result.map { |u| u["first_name"] }.sort,
                 "le joueur ET le co-organisateur qui ne joue pas sont des membres"
    assert_equal ["Membres du tournoi"], result.map { |u| u["group"] }.uniq
    refute result.any? { |u| u["already_organizer"] },
           "aucun ne doit être grisé : le promouvoir est le but du champ"
  end

  # Sur le champ de NOMINATION, à l'inverse, un co-organisateur qui ne joue pas n'a
  # rien à faire dans les suggestions — il gère déjà le tournoi.
  test "hors contexte transfert, un co-organisateur non joueur n'est pas suggéré" do
    @tournament.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    sign_in @admin

    get search_tournaments_path(tournament_id: @tournament.to_param)

    assert_empty JSON.parse(response.body)
  end

  # Une demande d'ami en attente n'est pas une amitié : elle ne doit rien suggérer.
  test "une demande d'ami non acceptée ne suggère personne" do
    Friendship.create!(user: @admin, friend: @co_org, status: "pending")
    sign_in @admin

    get search_tournaments_path

    assert_empty JSON.parse(response.body)
  end

  # La recherche libre reste ouverte à tous les utilisateurs : on ne fait que
  # remonter les inscrits et amis en tête.
  test "la recherche remonte l'ami en tête sans exclure les inconnus" do
    stranger = create_test_user(email: "stranger-org@example.com", first_name: "Dora", last_name: "Coorgi")
    Friendship.create!(user: @admin, friend: @co_org, status: "accepted")
    sign_in @admin

    get search_tournaments_path(q: "Coorg", tournament_id: @tournament.to_param)

    result = JSON.parse(response.body)
    assert_equal %w[Bob Dora], result.map { |u| u["first_name"] },
                 "l'ami passe devant l'inconnu"
    groups = result.map { |u| u["group"] }
    assert_equal ["Tes amis", nil], groups
    assert_includes result.map { |u| u["last_name"] }, stranger.profil.last_name
  end

  # L'endpoint ne doit jamais faire circuler d'email : seul un signed_id à durée de
  # vie courte identifie la personne (cf. docs/SECURITE-RGPD.md).
  test "les suggestions ne contiennent aucun email" do
    Friendship.create!(user: @admin, friend: @co_org, status: "accepted")
    sign_in @admin

    get search_tournaments_path

    result = JSON.parse(response.body)
    assert_equal %w[sgid first_name last_name group already_organizer].sort,
                 result.first.keys.sort
    refute_includes response.body, @co_org.email
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
