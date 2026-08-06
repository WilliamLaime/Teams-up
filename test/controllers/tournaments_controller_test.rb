# Tests d'intégration pour TournamentsController (Lot 2 : création)
# Vérifie le rendu du formulaire et le flux de création (admin, co-organisateur,
# auto-inscription optionnelle du créateur).
require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user       = create_test_user(email: "owner@example.com", first_name: "Alice", last_name: "Test")
    @co_org     = create_test_user(email: "coorg@example.com", first_name: "Bob",   last_name: "Test")
    @sport      = Sport.create!(name: "Padel Test", slug: "padel", icon: "🎾")
  end

  teardown { teardown_db }

  # ─── GET /tournois/bientot : page d'attente publique + non-indexée ──────────
  test "GET /tournois/bientot se rend pour un visiteur non connecté et est noindex" do
    get coming_soon_tournaments_path
    assert_response :success
    assert_select "meta[name=?][content*=?]", "robots", "noindex"
    assert_select ".tournament-soon__title"
  end

  # ─── GET /tournois : onglets + pagination (page liste) ──────────────────────
  def open_tournament(name, max_players: 8)
    Tournament.create!(name: name, sport: @sport, format: "poules", status: "open",
                       max_players: max_players, date: Date.tomorrow, place: "Terrain test")
  end

  test "GET /tournois sélectionne l'onglet 'mine' par défaut pour un inscrit actif" do
    sign_in @user
    t = open_tournament("Mon tournoi")
    t.tournament_users.create!(user: @user, role: "joueur", status: "approved")

    get tournaments_path
    assert_response :success
    assert_select ".tournaments-index-tabs__tab.is-active", text: /Mes tournois/
  end

  test "GET /tournois?tab=join exclut les tournois complets" do
    sign_in @user
    full = open_tournament("Complet", max_players: 1)
    full.tournament_users.create!(user: @co_org, role: "joueur", status: "approved")
    ouvert = open_tournament("Ouvert", max_players: 8)

    get tournaments_path(tab: "join")
    assert_response :success
    assert_match ouvert.name, response.body
    assert_no_match(/#{Regexp.escape(full.name)}/, response.body)
  end

  test "GET /tournois?tab=join pagine à 9 par page" do
    10.times { |i| open_tournament("Pagination #{i}") }

    get tournaments_path(tab: "join")
    assert_response :success
    assert_select ".row.row-cols-1 > .col", 9

    get tournaments_path(tab: "join", page: 2)
    assert_select ".row.row-cols-1 > .col", 1
  end

  test "GET /tournois masque l'onglet 'Mes tournois' pour un visiteur non connecté" do
    get tournaments_path
    assert_response :success
    assert_select ".tournaments-index-tabs__tab", text: /Mes tournois/, count: 0
  end

  test "GET /tournois conserve query et sport dans les liens d'onglet" do
    get tournaments_path(query: "Padel", tab: "completed")
    assert_response :success
    assert_select ".tournaments-index-tabs__tab[href*=?]", "query=Padel"
  end

  # ─── GET /tournois/new : le formulaire se rend (ERB compile) ────────────────
  test "GET /tournois/new retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get new_tournament_path
    assert_response :success
    assert_select "form"
    assert_select ".match-form-section", 4 # 4 sections numérotées

    # Bannière pilotée par le sport (Lot 7) : la cible du JS et le champ persisté.
    assert_select "#tournament-new-banner"
    assert_select "input[name='tournament[banner_image]']"
    assert_select "input[data-tournament-form-target='sportInput'][data-images]"

    # Réglages de structure personnalisables + plus aucun champ heure de début.
    assert_select ".tournament-advanced"
    assert_select "input[name='tournament[players_per_pool]']"
    assert_select "select[name='tournament[bracket_size]']"
    assert_select "input[name='tournament[swiss_wins_to_qualify]']"
    assert_select "input[name='tournament[swiss_losses_to_eliminate]']"
    assert_select "input[name='tournament[time(4i)]']", 0
  end

  test "GET /tournois/new redirige un visiteur non connecté" do
    get new_tournament_path
    assert_response :redirect
  end

  # ─── POST /tournois : création nominale ─────────────────────────────────────
  test "POST /tournois crée un tournoi dont le créateur est l'admin non inscrit" do
    sign_in @user

    assert_difference "Tournament.count", 1 do
      post tournaments_path, params: {
        tournament: {
          name: "Open Test", sport_id: @sport.id, format: "ronde_suisse",
          max_players: 16, date: Date.tomorrow.to_s, place: "Club Test"
        }
      }
    end

    t = Tournament.last
    assert_equal @user, t.user # créateur = admin
    assert_equal "open", t.status
    assert_equal 0, t.approved_players_count # pas inscrit comme joueur par défaut
    assert_redirected_to tournament_path(t)
  end

  # ─── Bannière + réglages de structure (Lot 7) ───────────────────────────────
  test "POST /tournois persiste la bannière choisie et les réglages de structure" do
    sign_in @user
    banner = "https://res.cloudinary.com/test/image/upload/pingpong.png"

    post tournaments_path, params: {
      tournament: {
        name: "Open réglé", sport_id: @sport.id, format: "poules",
        max_players: 16, date: Date.tomorrow.to_s, place: "Club Test",
        banner_image: banner, players_per_pool: 8, bracket_size: 4
      }
    }

    t = Tournament.last
    assert_equal banner, t.banner_image, "l'image suivie du sport est enregistrée"
    assert_equal 8, t.pool_size
    assert_equal 4, t.final_size
    assert_equal "2 poules de 8 + demi-finales", t.structure_summary
  end

  test "POST /tournois : un réglage vide retombe sur la recommandation" do
    sign_in @user

    post tournaments_path, params: {
      tournament: {
        name: "Open auto", sport_id: @sport.id, format: "poules",
        max_players: 16, date: Date.tomorrow.to_s, place: "Club Test",
        players_per_pool: "", bracket_size: ""
      }
    }

    t = Tournament.last
    assert_nil t.players_per_pool
    assert_equal Tournament::DEFAULT_POOL_SIZE, t.pool_size
    assert_equal "4 poules de 4 + quarts", t.structure_summary
  end

  test "POST /tournois refuse un tableau final qui n'est pas une puissance de 2" do
    sign_in @user

    assert_no_difference "Tournament.count" do
      post tournaments_path, params: {
        tournament: {
          name: "Open cassé", sport_id: @sport.id, format: "poules",
          max_players: 16, date: Date.tomorrow.to_s, place: "Club Test",
          bracket_size: 6
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # ─── Co-organisateur + auto-inscription ─────────────────────────────────────
  test "POST /tournois avec co-organisateur et auto-inscription" do
    sign_in @user

    post tournaments_path, params: {
      tournament: {
        name: "Open Test 2", sport_id: @sport.id, format: "poules",
        max_players: 8, date: Date.tomorrow.to_s, place: "Club Test"
      },
      co_organizer_sgid: @co_org.invite_sgid,
      self_register: "1"
    }

    t = Tournament.last
    # Le créateur s'est auto-inscrit comme joueur → 1 place occupée
    assert_equal 1, t.approved_players_count
    # Le co-org existe mais n'occupe PAS de place de joueur
    assert t.tournament_users.exists?(user: @co_org, role: "co_organisateur")
    assert_equal 1, t.tournament_users.where(role: "joueur").count
    assert t.organizer?(@co_org)
  end

  # ─── GET /tournois/search : autocomplete co-organisateur ────────────────────
  test "GET /tournois/search renvoie du JSON filtré" do
    sign_in @user
    get search_tournaments_path(q: "Bob"), headers: { "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    # On identifie les résultats par leur sgid, jamais par leur email (voir plus bas)
    assert(body.any? { |u| User.find_by_invite_sgid(u["sgid"]) == @co_org })
    refute(body.any? { |u| User.find_by_invite_sgid(u["sgid"]) == @user }) # s'exclut lui-même
  end

  # ─── Sécurité : pas d'énumération d'emails via l'autocomplete ───────────────
  # Un ILIKE sur users.email permettrait de lister les comptes en cherchant
  # « @example.com ». Voir docs/SECURITE-RGPD.md.
  test "GET /tournois/search ne permet pas d'énumérer les emails" do
    sign_in @user
    get search_tournaments_path(q: "@example.com"), headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "GET /tournois/search trouve un joueur par son email exact" do
    sign_in @user
    get search_tournaments_path(q: @co_org.email), headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    assert(body.any? { |u| User.find_by_invite_sgid(u["sgid"]) == @co_org })
  end

  test "GET /tournois/search ne renvoie jamais d'email" do
    sign_in @user
    get search_tournaments_path(q: "Bob"), headers: { "Accept" => "application/json" }
    refute_includes response.body, "@example.com"
    JSON.parse(response.body).each { |u| refute_includes u.keys, "email" }
  end

  test "POST /tournois ignore un co_organizer_sgid forgé" do
    sign_in @user

    post tournaments_path, params: {
      tournament: {
        name: "Open Test 3", sport_id: @sport.id, format: "poules",
        max_players: 8, date: Date.tomorrow.to_s, place: "Club Test"
      },
      co_organizer_sgid: "sgid-bidon"
    }

    t = Tournament.last
    assert_empty t.tournament_users.where(role: "co_organisateur")
  end

  test "GET /tournois/search retourne vide sous 3 caractères" do
    sign_in @user
    get search_tournaments_path(q: "Bo"), headers: { "Accept" => "application/json" }
    assert_equal [], JSON.parse(response.body)
  end

  # ─── POST /tournois/:id/start : lancement (Lot 3) ───────────────────────────
  def open_tournament_with_players(count)
    t = Tournament.create!(name: "Start Test", sport: @sport, user: @user,
                           format: "ronde_suisse", status: "open", max_players: count,
                           date: Date.tomorrow, place: "Terrain test")
    count.times do |i|
      u = create_test_user(email: "sp#{i}@example.com")
      t.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    t
  end

  test "POST start lance le tournoi et crée la ronde 1 (organisateur)" do
    sign_in @user
    t = open_tournament_with_players(8)

    post start_tournament_path(t)

    assert_equal "in_progress", t.reload.status
    assert_equal 1, t.swiss_rounds.count
    assert t.swiss_rounds.first.tournament_matches.any?
  end

  test "POST start fige un vrai tirage au sort (draw_order mélangé, pas l'ordre d'inscription)" do
    sign_in @user
    t = open_tournament_with_players(8)
    ids_by_registration_order = t.tournament_users.players.approved.order(:id).pluck(:id)

    # Shuffle déterministe pour un test reproductible : on fixe la graine, on la
    # restaure après (ne doit pas fuiter sur les autres tests de la suite).
    seed_before = srand(42)
    post start_tournament_path(t)
    srand(seed_before)

    approved = t.tournament_users.players.approved.reload
    # draw_order forme bien une permutation complète de 0..7 (chacun assigné une fois).
    assert_equal (0..7).to_a, approved.pluck(:draw_order).sort

    # Avec la graine fixée, l'ordre résultant (trié par draw_order) diffère de
    # l'ordre d'inscription (id) — preuve que ce n'est pas juste id repeint en
    # draw_order, mais un vrai mélange.
    ids_by_draw_order = approved.order(:draw_order).pluck(:id)
    assert_not_equal ids_by_registration_order, ids_by_draw_order
  end

  test "POST start refuse un non-organisateur" do
    sign_in @co_org # ni admin ni co-org de ce tournoi
    t = open_tournament_with_players(8)
    status_before = t.reload.status # "closed" : complet dès le 8e inscrit (cf. auto-clôture)

    post start_tournament_path(t)
    assert_response :redirect
    assert_equal status_before, t.reload.status # inchangé : le tiers n'a pas pu lancer
  end

  test "POST start refuse un effectif insuffisant" do
    sign_in @user
    # 1 seul joueur pour 1 place : le tournoi se clôture tout seul (complet, cf.
    # Tournament#close_registrations_if_full!) mais reste sous le seuil de lancement.
    t = open_tournament_with_players(1)

    post start_tournament_path(t)
    assert_not_equal "in_progress", t.reload.status
    assert_redirected_to tournament_path(t)
  end

  test "GET show : la Vue d'ensemble affiche des noms cliquables vers le profil (bracket viewer)" do
    sign_in @user
    # 4 joueurs, final_size = 4 → SwissPairing saute direct au tableau final (cf.
    # SwissPairing#ready_for_bracket?), donc bracket_rounds existe dès le lancement
    # et le bracket viewer (Vue d'ensemble) rend bien des _bracket_cell.
    t = open_tournament_with_players(4)

    post start_tournament_path(t)
    assert t.reload.bracket_started?

    get tournament_path(t)
    assert_response :success
    assert_select "a.bracket-cell__player-link[href=?]", user_profil_path(t.tournament_users.players.first.user)
  end

  # ─── GET /tournois/:id : rendu du board (le partiel ERB compile) ────────────
  test "GET show rend le panneau de lancement pour un tournoi ouvert" do
    sign_in @user
    t = open_tournament_with_players(8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-start-panel"
  end

  test "GET show rend les rondes suisses pour un tournoi lancé" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round!

    get tournament_path(t)
    assert_response :success
    assert_select ".round-col"
    assert_select ".tmatch-card"
  end

  test "GET show : pas de panneau Qualifiés/Éliminés tant que personne n'a 3 victoires ou 3 défaites" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round! # Ronde 1 : tout le monde à 0V-0D

    get tournament_path(t)
    assert_response :success
    assert_select ".qualification-col", 0
  end

  test "GET show : le panneau Qualifiés/Éliminés liste les joueurs à 3 victoires ou 3 défaites" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")

    20.times do
      break if t.reload.tournament_users.any?(&:qualified?)

      SwissPairing.new(t).next_round!
      t.current_round.tournament_matches.where(status: "pending", is_bye: false)
       .find_each { |m| win_tournament_match!(m, m.player_a) }
    end
    assert t.reload.tournament_users.any?(&:qualified?), "au moins un joueur devrait être qualifié"

    get tournament_path(t)
    assert_response :success
    assert_select ".qualification-col"
    assert_select ".qualification-col__title--qualified"
    assert_select ".qualification-col__title--eliminated"
  end

  test "GET show : pas de panneau Qualifiés/Éliminés pour un format championnat" do
    sign_in @user
    t = launched_tournament("championnat", 8)
    get tournament_path(t)
    assert_response :success
    assert_select ".qualification-col", 0
  end

  test "GET show : le sélecteur de phase (2 pastilles) apparaît dès le lancement (Lot 7, structure complète)" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round! # Ronde 1, tableau final pas encore démarré

    get tournament_path(t)
    assert_response :success
    assert_select ".phase-nav__pill", 2
  end

  test "GET show : le tableau final affiche la structure complète avec des cases « À déterminer » avant d'être démarré" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round! # Ronde 1, tableau final pas encore démarré
    assert_not t.reload.bracket_started?

    get tournament_path(t)
    assert_response :success
    # final_size 4 (8 joueurs) → 2 tours prévus (demies, finale), aucun encore joué.
    assert_select ".bracket__round", 2
    assert_select ".tmatch-card--placeholder", 3 # 2 places en demies + 1 en finale
  end

  test "GET show : la recherche de participants apparaît au-delà de 8 joueurs" do
    sign_in @user
    t = open_tournament_with_players(12)

    get tournament_path(t)
    assert_response :success
    assert_select ".participant-search__input"
    # Chaque carte est filtrable et porte le nom sur lequel comparer.
    assert_select ".participant-chip[data-participant-filter-target=card]", 12
    assert_select ".participant-chip[data-name=?]", t.approved_players.first.display_name.downcase
  end

  test "GET show : pas de recherche de participants sur une petite grille" do
    sign_in @user
    t = open_tournament_with_players(8)

    get tournament_path(t)
    assert_response :success
    assert_select ".participant-search", 0
    assert_select ".participant-chip[data-participant-filter-target=card]", 0
  end

  test "GET show : un qualifié monte d'une case sans attendre son adversaire" do
    sign_in @user
    t = launched_tournament("ronde_suisse", 8)
    finalists = t.tournament_users.players.approved.order(:id).first(4)
    semis = BracketBuilder.new(t, finalists: finalists).build!
    won = semis.tournament_matches.order(:position).first
    won.update!(sets: [[6, 0], [6, 0]]) # 1re demie jouée, la 2e non → finale à moitié connue

    get tournament_path(t)
    assert_response :success
    # La finale n'existe pas encore en base : sa case affiche le vainqueur connu…
    assert_select ".tmatch-card--placeholder-known", 1
    assert_select ".tmatch-card--placeholder-known .tmatch-card__name",
                  text: won.reload.winner.display_name
    # …et laisse UN seul camp en attente.
    assert_select ".tmatch-card--placeholder-known .tmatch-card__player--pending", 1
    # La case entièrement inconnue reste, elle, sans joueur.
    assert_select ".tmatch-card--placeholder:not(.tmatch-card--placeholder-known)", 0
  end

  test "GET show : le tableau final reste affiché même si `playoffs` vaut false sur un tournoi non-championnat" do
    # Régression : `playoffs` n'a de sens que pour le championnat (LeagueBuilder),
    # mais la colonne existe pour tous les formats — une ronde suisse/poules avec
    # playoffs: false en base (valeur non pertinente pour son moteur) doit quand
    # même afficher son tableau final, cf. Tournament#bracket_expected?.
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress", playoffs: false)
    SwissPairing.new(t).next_round! # Ronde 1, tableau final pas encore démarré

    get tournament_path(t)
    assert_response :success
    assert_select ".phase-nav__pill", 2
    assert_select ".bracket__round", 2
  end

  test "GET show : le sélecteur de phase (2 pastilles) reste présent une fois le tableau final démarré" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")

    20.times do
      break if t.reload.bracket_started?

      SwissPairing.new(t).next_round!
      t.current_round.tournament_matches.where(status: "pending", is_bye: false)
       .find_each { |m| win_tournament_match!(m, m.player_a) }
    end
    assert t.reload.bracket_started?, "le tournoi devrait avoir atteint le tableau final"

    get tournament_path(t)
    assert_response :success
    assert_select ".phase-nav__pill", 2
  end

  test "GET show affiche les pastilles de bracket de score à partir de la ronde 2" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round! # Ronde 1

    get tournament_path(t)
    assert_response :success
    # Ronde 1 : un seul groupe possible (0V-0D pour tout le monde) → pas de pastille.
    assert_select ".score-bracket__pip", 0

    t.swiss_rounds.first.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(t).next_round! # Ronde 2 : 2 groupes (1V-0D / 0V-1D)

    get tournament_path(t)
    assert_response :success
    assert_select ".score-bracket__pip", minimum: 1
  end

  test "GET show : les boutons vainqueur n'apparaissent que pour l'organisateur" do
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round!

    sign_in @co_org # non-organisateur
    get tournament_path(t)
    assert_select ".round-col" # les rondes sont bien affichées
    assert_select ".tmatch-card__win-btn", 0 # mais aucun bouton vainqueur
  end

  # ─── Formats Lot 5 : rendu des nouvelles vues (les partials ERB compilent) ────
  def launched_tournament(format, count)
    t = Tournament.create!(name: "Fmt #{format}", sport: @sport, user: @user,
                           format: format, status: "open", max_players: count,
                           date: Date.tomorrow, place: "Terrain test")
    count.times do |i|
      u = create_test_user(email: "f-#{format}-#{i}@example.com")
      t.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    t.update!(status: "in_progress")
    TournamentEngine.for(t).next_round!
    t
  end

  # Repère « moi » : sans lui, retrouver son match dans une grille de 8 poules
  # demande de lire chaque nom. Le test vérifie surtout qu'il ne se déclenche QUE
  # pour le joueur concerné — un repère qui s'allume pour tout le monde ne repère rien.
  test "GET show met en avant les matchs et la ligne de classement du joueur connecté" do
    t = launched_tournament("poules", 8)
    me = t.tournament_users.players.approved.order(:id).first

    sign_in me.user
    get tournament_path(t)
    assert_response :success
    assert_select ".tmatch-card--mine", 1 # un seul match par journée
    assert_select ".pool-grid__col--mine", 1
    assert_select ".tmatch-card__me-badge"
    assert_select ".tournament-ranking__row.is-me", 1

    # L'organisateur, lui, ne joue pas : aucun repère ne doit s'allumer.
    sign_in @user
    get tournament_path(t)
    assert_response :success
    assert_select ".tmatch-card--mine", 0
    assert_select ".pool-grid__col--mine", 0
    assert_select ".tournament-ranking__row.is-me", 0
  end

  test "GET show rend la phase championnat" do
    sign_in @user
    t = launched_tournament("championnat", 8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-phase__title", text: "Championnat"
    assert_select ".round-col"
  end

  test "GET show : le championnat propose un sélecteur de journée (menu déroulant)" do
    sign_in @user
    t = launched_tournament("championnat", 8) # crée la journée 1 (in_progress)

    # Termine la journée 1 → la journée 2 est créée, pour avoir 2 options à tester.
    t.league_rounds.first.tournament_matches.each { |m| win_tournament_match!(m, m.player_a) }
    LeagueBuilder.new(t).next_round!

    get tournament_path(t)
    assert_response :success
    assert_select ".journee-picker__toggle span", text: "Journée 2" # présélection sur la journée en cours
    assert_select ".journee-picker__option", 2
    # Filtre multi-sélection : une case à cocher par journée, seule celle de la
    # journée en cours est cochée au chargement.
    assert_select ".journee-picker__option input[type=checkbox][data-round-number=?][checked]", "2"
    assert_select ".journee-picker__option input[type=checkbox][data-round-number=?]:not([checked])", "1"
    assert_select ".journee-picker__all input[type=checkbox]" # raccourci « toutes les journées »
    # Seule la journée en cours (2) est visible au chargement, la 1ère est masquée.
    assert_select ".round-ribbon__page[data-round-number=?][hidden]", "1"
    assert_select ".round-ribbon__page[data-round-number=?]:not([hidden])", "2"
  end

  test "GET show : la scoreline affiche le vrai score pour un sport à score simple (pas 1-0/0-0)" do
    sign_in @user
    football = Sport.find_or_create_by!(slug: "football") { |s| s.name = "Football"; s.icon = "⚽" }
    t = Tournament.create!(name: "Foot Test", sport: football, user: @user, format: "championnat",
                           status: "open", max_players: 8, date: Date.tomorrow, place: "Terrain test")
    8.times do |i|
      u = create_test_user(email: "foot-#{i}@example.com")
      t.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    t.update!(status: "in_progress")
    TournamentEngine.for(t).next_round!

    match = t.league_rounds.first.tournament_matches.first
    match.assign_score([[3, 2]]) # score réel, PAS un "set" à 1-0
    match.save!

    get tournament_path(t)
    assert_response :success
    assert_select ".tmatch-card__center-score", text: "3"
    assert_select ".tmatch-card__center-score", text: "2"
  end

  test "GET show rend la phase poules (matchs groupés par poule)" do
    sign_in @user
    t = launched_tournament("poules", 8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-phase__title", text: "Poules"
    assert_select ".pool-label"
  end

  test "GET show : bouton forfait visible pour l'organisateur d'un tournoi en cours" do
    sign_in @user
    t = launched_tournament("championnat", 8)
    get tournament_path(t)
    assert_select ".participant-chip__forfeit"
  end

  # ─── GET/PATCH édition : ouverte à l'admin ET au co-organisateur ────────────
  def tournament_with_co_org
    t = open_tournament("Éditable")
    t.update!(user: @user)
    t.tournament_users.create!(user: @co_org, role: "co_organisateur", status: "approved")
    t
  end

  test "GET edit autorisé pour l'admin" do
    sign_in @user
    t = tournament_with_co_org
    get edit_tournament_path(t)
    assert_response :success
    assert_select "form"
  end

  test "GET edit autorisé pour le co-organisateur" do
    sign_in @co_org
    t = tournament_with_co_org
    get edit_tournament_path(t)
    assert_response :success
  end

  test "GET edit refusé pour un tiers" do
    sign_in create_test_user(email: "tiers@example.com")
    t = tournament_with_co_org
    get edit_tournament_path(t)
    assert_response :redirect
  end

  test "PATCH update modifie la date par l'admin" do
    sign_in @user
    t = tournament_with_co_org
    new_date = 3.days.from_now.to_date

    patch tournament_path(t), params: { tournament: { date: new_date.to_s } }

    assert_redirected_to tournament_path(t)
    assert_equal new_date, t.reload.date
  end

  test "PATCH update modifie la date par le co-organisateur" do
    sign_in @co_org
    t = tournament_with_co_org
    new_date = 3.days.from_now.to_date

    patch tournament_path(t), params: { tournament: { date: new_date.to_s } }
    assert_equal new_date, t.reload.date
  end

  test "PATCH update ignore format/max_players une fois le tournoi lancé" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")

    patch tournament_path(t), params: { tournament: { format: "poules", max_players: 32, place: "Nouveau lieu" } }

    t.reload
    assert_equal "ronde_suisse", t.format # inchangé
    assert_equal 8, t.max_players         # inchangé
    assert_equal "Nouveau lieu", t.place  # champ non structurel, bien mis à jour
  end

  # ─── PATCH toggle_registrations : clôture/réouverture manuelle ──────────────
  test "PATCH toggle_registrations clôture puis rouvre" do
    sign_in @user
    t = tournament_with_co_org
    assert t.open?

    patch toggle_registrations_tournament_path(t)
    assert_equal "closed", t.reload.status

    patch toggle_registrations_tournament_path(t)
    assert_equal "open", t.reload.status
  end

  test "PATCH toggle_registrations refuse un non-organisateur" do
    sign_in create_test_user(email: "tiers2@example.com")
    t = tournament_with_co_org

    patch toggle_registrations_tournament_path(t)
    assert_equal "open", t.reload.status
  end

  # ─── PATCH finish : fin manuelle ─────────────────────────────────────────────
  test "PATCH finish termine un tournoi en cours" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")

    patch finish_tournament_path(t)
    assert_equal "completed", t.reload.status
  end

  test "PATCH finish est sans effet si déjà terminé" do
    sign_in @user
    t = tournament_with_co_org
    t.update!(status: "completed")

    patch finish_tournament_path(t)
    assert_equal "completed", t.reload.status
  end

  # ─── Rendu : badge "closed" + bouton Rouvrir + lien Modifier ────────────────
  test "GET show rend le badge Inscriptions closes et le bouton Rouvrir pour l'organisateur" do
    sign_in @user
    t = tournament_with_co_org
    t.update!(status: "closed")

    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-status-badge--closed", text: /Inscriptions closes/
    assert_select ".tournament-start-panel form[action=?]", toggle_registrations_tournament_path(t)
    assert_select ".tournament-edit-link"
  end
end
