# Tests d'intégration pour MatchesController
# On utilise ActionDispatch::IntegrationTest (test HTTP complet, pas de test unitaire controller)
# Devise::Test::IntegrationHelpers fournit sign_in pour simuler un utilisateur connecté
require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  # On inclut les helpers Devise pour pouvoir appeler sign_in dans les tests
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes à tous les tests ──────────────────────────────
  # On crée les données directement en base (pas via fixtures) pour contrôler
  # exactement l'état de départ de chaque test.
  setup do
    # Utilisateur propriétaire du match (organisateur).
    # create_test_user crée le User + le Profil en une seule opération.
    # Sans le Profil, certaines vues Rails planteraient sur user.profil.first_name.
    @user = create_test_user(email: "owner@example.com", first_name: "Alice", last_name: "Test")

    # Deuxième utilisateur (joueur lambda, pas organisateur)
    @other_user = create_test_user(email: "other@example.com", first_name: "Bob", last_name: "Test")

    # Sport nécessaire pour créer un match
    @sport = Sport.create!(name: "Football Test", slug: "football-test", icon: "⚽")

    # Match public dans le futur (cas nominal)
    @match = Match.create!(
      title: "Match test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      players_needed: 4,
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @user,
      sport: @sport
    )

    # Ajoute @user comme organisateur du match
    @match.match_users.create!(user: @user, role: "organisateur", status: "approved")
  end

  # ─── teardown : nettoyage complet dans l'ordre FK ───────────────────────────
  # On utilise teardown_db (défini dans test_helper.rb) qui supprime toutes les
  # tables dans le bon ordre pour éviter les violations de contrainte FK.
  # C'est nécessaire car les fixtures (users :one, :two) ont des friendships/teams
  # qui référencent les users — PostgreSQL refuse de les supprimer si des FK pointent dessus.
  teardown do
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches — action index
  # ════════════════════════════════════════════════════════════════════════════

  # matches#index est public (skip_before_action :authenticate_user!) → 200 pour tout le monde
  test "GET /matches retourne 200 pour un visiteur non connecté" do
    get matches_path
    assert_response :success
  end

  # Cas nominal : un utilisateur connecté peut aussi voir la liste des matchs
  test "GET /matches retourne 200 pour un user connecté" do
    sign_in @user
    get matches_path
    assert_response :success
  end

  # Cas ?mine=1 : filtre "mes matchs" — ne montre que les matchs de l'user connecté
  test "GET /matches?mine=1 retourne 200 pour un user connecté" do
    sign_in @user
    get matches_path, params: { mine: "1" }
    assert_response :success
  end

  # Cas ?mine=1&status=completed : matchs terminés de l'user connecté
  test "GET /matches?mine=1&status=completed retourne 200" do
    sign_in @user
    get matches_path, params: { mine: "1", status: "completed" }
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/:id — action show
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root, même pour
  # un match public — la landing guard s'active avant la logique du controller.
  # Un user connecté peut voir le match.
  test "GET /matches/:id retourne 200 pour un match public si connecté" do
    sign_in @user
    get match_path(@match)
    assert_response :success
  end

  # matches#show est public (skip_before_action :authenticate_user!) → 200 pour tout le monde
  test "GET /matches/:id retourne 200 pour un visiteur non connecté" do
    get match_path(@match)
    assert_response :success
  end

  # Cas d'erreur : un user connecté sur un match privé sans token → redirigé vers root
  # La guard MatchesController#show vérifie le token pour les non-organisateurs.
  test "GET /matches/:id redirige vers root pour un match privé sans token (connecté)" do
    # On crée un match privé appartenant à @other_user
    private_match = Match.create!(
      title: "Match privé",
      date: Date.tomorrow,
      time: Time.current.change(hour: 19, min: 0),
      players_needed: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @other_user,
      sport: @sport,
      private_token: SecureRandom.hex(8)
    )

    # @user est connecté mais n'est pas l'organisateur et n'a pas le token
    sign_in @user
    get match_path(private_match)
    assert_redirected_to root_path
  ensure
    private_match&.destroy
  end

  # Cas nominal : un user connecté peut accéder à un match privé avec le bon token.
  # ATTENTION : le before_create :generate_private_token écrase toujours private_token,
  # même si on en passe un à la création. Il faut donc lire le token APRÈS creation.
  test "GET /matches/:id retourne 200 pour un match privé avec le bon token (connecté)" do
    private_match = Match.create!(
      title: "Match privé avec token",
      date: Date.tomorrow,
      time: Time.current.change(hour: 20, min: 0),
      players_needed: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @other_user,
      sport: @sport
    )
    # Le callback before_create a généré un token aléatoire — on le lit après création
    generated_token = private_match.private_token

    sign_in @user
    # On utilise le token réellement généré
    get match_path(private_match), params: { token: generated_token }
    assert_response :success
  ensure
    private_match&.destroy
  end

  # Cas nominal : l'organisateur peut toujours accéder à son match privé
  test "GET /matches/:id retourne 200 pour l'organisateur d'un match privé" do
    private_match = Match.create!(
      title: "Match privé organisateur",
      date: Date.tomorrow,
      time: Time.current.change(hour: 21, min: 0),
      players_needed: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @user,       # @user est l'organisateur
      sport: @sport,
      private_token: "secrettoken"
    )

    sign_in @user
    # L'organisateur accède sans token — il a toujours accès
    get match_path(private_match)
    assert_response :success
  ensure
    private_match&.destroy
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/new — formulaire de création
  # ════════════════════════════════════════════════════════════════════════════

  # Visiteur non connecté → Devise redirige vers la page de login
  test "GET /matches/new redirige vers login si non connecté" do
    get new_match_path
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : un utilisateur connecté peut voir le formulaire
  test "GET /matches/new retourne 200 si connecté" do
    sign_in @user
    get new_match_path
    assert_response :success
  end

  # Régression : sans sport actif (mode multisport « Tous les sports » où
  # current_sport = nil), un sport doit tout de même être présélectionné.
  # Sinon le JS (updateSport) ne génère aucun bouton de niveau ni format et
  # le champ « Niveau requis » reste vide au chargement du formulaire.
  test "GET /matches/new présélectionne un sport même sans sport actif" do
    # @user n'a aucun sport ni current_sport_id → current_sport renvoie nil
    sign_in @user
    get new_match_path
    assert_response :success
    # Le placeholder ne doit PAS apparaître : un sport réel est présélectionné
    assert_not_includes response.body, "Sélectionner un sport",
                        "Aucun sport présélectionné → le champ Niveau resterait vide"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /matches — création d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Visiteur non connecté → Devise redirige vers la page de login
  test "POST /matches redirige vers login si non connecté" do
    post matches_path, params: {
      match: { title: "Test", date: Date.tomorrow, time: "18:00",
               level: "Débutant", players_needed: 4, sport_id: @sport.id,
               visibility: "public", validation_mode: "automatic",
               genre_restriction: "tous" }
    }
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : un match valide est créé et on est redirigé vers sa page
  test "POST /matches crée le match et redirige si params valides" do
    sign_in @user
    assert_difference "Match.count", 1 do
      post matches_path, params: {
        match: {
          title: "Nouveau match",
          date: Date.tomorrow,
          time: "18:00",
          level: "Débutant",
          players_needed: 4,
          sport_id: @sport.id,
          visibility: "public",
          validation_mode: "automatic",
          genre_restriction: "tous"
        }
      }
    end
    # Après création réussie, on redirige vers la page du match
    assert_redirected_to match_path(Match.last)
  end

  # ─── Retour au tournoi après « Publier le match » ───────────────────────────
  # Une rencontre planifiée depuis une carte de tournoi doit ramener AU TOURNOI :
  # celui qui vient de caler son créneau veut le voir apparaître dans le board et
  # le calendrier, pas atterrir sur la page du match et refaire tout le chemin
  # pour planifier la suivante.
  test "POST /matches redirige vers le tournoi quand la rencontre en fait partie" do
    sign_in @user
    tournament = Tournament.create!(name: "Tournoi retour", sport: @sport, user: @user,
                                    format: "poules", status: "in_progress", max_players: 8,
                                    date: Date.tomorrow, place: "Terrain test")

    assert_difference "Match.count", 1 do
      post matches_path, params: {
        match: {
          title: "Rencontre de tournoi",
          date: Date.tomorrow,
          time: "18:00",
          level: "Débutant",
          players_needed: 2,
          sport_id: @sport.id,
          tournament_id: tournament.id,
          visibility: "public",
          validation_mode: "automatic",
          genre_restriction: "tous"
        }
      }
    end

    assert_redirected_to tournament_path(tournament)
  end

  # Cas d'erreur : des params invalides (level manquant) réaffichent le formulaire
  test "POST /matches réaffiche le formulaire (422) si params invalides" do
    sign_in @user
    assert_no_difference "Match.count" do
      post matches_path, params: {
        match: {
          title: "",         # titre vide → invalide
          date: Date.tomorrow,
          time: "18:00",
          level: "",         # level manquant → invalide
          players_needed: 0,    # 0 = invalide
          sport_id: @sport.id
        }
      }
    end
    # 422 Unprocessable Entity = formulaire réaffiché avec erreurs
    assert_response :unprocessable_entity
  end

  # Cas sécurité : un homme ne peut pas créer un match "feminin"
  # Le controller force genre_restriction à "tous" pour les non-femmes
  test "POST /matches force genre_restriction à 'tous' pour un non-femme" do
    sign_in @user # @user n'a pas de genre = pas femme
    post matches_path, params: {
      match: {
        title: "Match masculin",
        date: Date.tomorrow,
        time: "18:00",
        level: "Débutant",
        players_needed: 4,
        sport_id: @sport.id,
        visibility: "public",
        validation_mode: "automatic",
        genre_restriction: "feminin"  # Valeur qu'on tente d'envoyer frauduleusement
      }
    }
    # Le match a été créé
    assert_redirected_to match_path(Match.last)
    # Mais genre_restriction a été forcé à "tous"
    assert_equal "tous", Match.last.genre_restriction
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/:id/edit — formulaire de modification
  # ════════════════════════════════════════════════════════════════════════════

  # Visiteur non connecté → Devise redirige vers la page de login
  test "GET /matches/:id/edit redirige vers login si non connecté" do
    get edit_match_path(@match)
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : l'organisateur peut voir le formulaire d'édition
  test "GET /matches/:id/edit retourne 200 pour l'organisateur" do
    sign_in @user
    get edit_match_path(@match)
    assert_response :success
  end

  # Cas d'erreur Pundit : un autre utilisateur est redirigé avec alert
  test "GET /matches/:id/edit redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    get edit_match_path(@match)
    # Pundit lève NotAuthorizedError → ApplicationController redirige avec flash[:alert]
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:id — mise à jour d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut mettre à jour son match
  test "PATCH /matches/:id met à jour et redirige si organisateur et params valides" do
    sign_in @user
    patch match_path(@match), params: {
      match: { title: "Titre mis à jour" }
    }
    assert_redirected_to match_path(@match)
    # Vérifie que le titre a bien été modifié en base
    assert_equal "Titre mis à jour", @match.reload.title
  end

  # Cas d'erreur : params invalides → réaffiche le formulaire
  test "PATCH /matches/:id réaffiche le formulaire (422) si params invalides" do
    sign_in @user
    patch match_path(@match), params: {
      match: { players_needed: -5 }  # valeur négative = invalide
    }
    assert_response :unprocessable_entity
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "PATCH /matches/:id redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    patch match_path(@match), params: { match: { title: "Tentative de modification" } }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /matches/:id — suppression d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut supprimer son match
  test "DELETE /matches/:id détruit le match et redirige si organisateur" do
    sign_in @user
    assert_difference "Match.count", -1 do
      delete match_path(@match)
    end
    assert_redirected_to matches_path
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "DELETE /matches/:id redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    assert_no_difference "Match.count" do
      delete match_path(@match)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:id/make_public — passer un match privé en public
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut rendre son match public
  test "PATCH /matches/:id/make_public passe le match en public si organisateur" do
    sign_in @user
    # On rend le match privé avant le test
    @match.update!(visibility: "private", private_token: "testtoken")

    patch make_public_match_path(@match)
    assert_redirected_to match_path(@match)
    assert_equal "public", @match.reload.visibility
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "PATCH /matches/:id/make_public redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    @match.update!(visibility: "private", private_token: "testtoken2")

    patch make_public_match_path(@match)
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Couplage Match ↔ tournoi (Lot 4)
  # ════════════════════════════════════════════════════════════════════════════

  # Crée un tournoi organisé par @user avec deux joueurs approuvés et une carte
  # de match suisse prête à être « transformée » en rencontre standard.
  def build_tournament_match(owner: @user, sport: @sport)
    tournament = Tournament.create!(name: "Tournoi test", sport: sport, user: owner,
                                    format: "ronde_suisse", status: "in_progress", max_players: 8,
                                    date: Date.tomorrow, place: "Terrain test", time: "18:00")
    player_b_user = create_test_user(email: "tplayer-#{SecureRandom.hex(3)}@example.com")
    a = tournament.tournament_users.create!(user: owner, role: "joueur", status: "approved")
    b = tournament.tournament_users.create!(user: player_b_user, role: "joueur", status: "approved")
    round = tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    match = round.tournament_matches.create!(player_a: a, player_b: b, position: 0)
    [tournament, match]
  end

  test "GET /matches/new depuis une carte de tournoi préremplit le formulaire" do
    sign_in @user
    tournament, tmatch = build_tournament_match

    get new_match_path(tournament_match_id: tmatch.id)
    assert_response :success

    # Lieu, date et heure du tournoi repris dans le formulaire (préremplissage).
    assert_match(/value="Terrain test"/, response.body)
    assert_match(/value="#{tournament.date}"/, response.body)
    assert_includes response.body[/<input[^>]*name="match\[time\(4i\)\]"[^>]*>/], 'value="18"'
    assert_includes response.body[/<input[^>]*name="match\[time\(5i\)\]"[^>]*>/], 'value="0"'
  end

  # ── Formulaire allégé en contexte tournoi ──────────────────────────────────
  # Une confrontation est un 1v1 entre deux joueurs déjà connus et inscrits par
  # le tournoi : la section « Détails du match » n'a pas lieu d'être.

  test "GET /matches/new depuis une carte de tournoi masque les détails du match" do
    sign_in @user
    _tournament, tmatch = build_tournament_match

    get new_match_path(tournament_match_id: tmatch.id)
    assert_response :success

    assert_no_match(/Détails du match/, response.body)
    assert_select "[data-match-form-target='formatWrapper']", 0
    assert_select "[data-match-form-target='levelButtons']", 0
    assert_select "[data-match-form-target='priceInput']", 0
  end

  test "GET /matches/new depuis une carte de tournoi soumet les valeurs imposées en caché" do
    sign_in @user
    _tournament, tmatch = build_tournament_match

    get new_match_path(tournament_match_id: tmatch.id)

    # Les deux seules valeurs que le modèle exige et qui n'ont plus de champ visible.
    assert_select "input[type=hidden][name='match[level]'][value='Tout niveau']"
    assert_select "input[type=hidden][name='match[players_needed]'][value='2']"
  end

  # Non-régression : hors tournoi, le formulaire complet est toujours rendu.
  test "GET /matches/new sans tournoi conserve la section Détails du match" do
    sign_in @user

    get new_match_path
    assert_response :success

    assert_match(/Détails du match/, response.body)
    assert_select "[data-match-form-target='formatWrapper']"
  end

  # ── Bannière : une image DU SPORT du tournoi, connue dès le rendu serveur ───

  test "GET /matches/new depuis un tournoi de ping-pong affiche une bannière ping-pong" do
    sign_in @user
    pingpong = Sport.find_by(slug: "ping-pong") ||
               Sport.create!(name: "Ping-Pong Test", slug: "ping-pong", icon: "🏓")
    _tournament, tmatch = build_tournament_match(sport: pingpong)

    get new_match_path(tournament_match_id: tmatch.id)
    assert_response :success

    # Le fond est peint côté serveur (pas de clignotement au chargement du JS)…
    banner = response.body[/<div class="match-new-banner"[^>]*>/]
    assert_match %r{sports/ping-pong/}, banner

    # …et le champ caché soumis pointe sur exactement la même image.
    hidden = response.body[/<input[^>]*name="match\[banner_image\]"[^>]*>/]
    assert_match %r{sports/ping-pong/}, hidden
  end

  test "GET /matches/new écarte une bannière de tournoi étrangère au sport" do
    sign_in @user
    pingpong = Sport.find_by(slug: "ping-pong") ||
               Sport.create!(name: "Ping-Pong Test", slug: "ping-pong", icon: "🏓")
    tournament, tmatch = build_tournament_match(sport: pingpong)
    # Image hors de la banque du sport : le JS la remplacerait au chargement,
    # ce qui provoquerait le clignotement. Le serveur doit déjà l'avoir écartée.
    tournament.update!(banner_image: "https://example.com/pas-du-ping-pong.png")

    get new_match_path(tournament_match_id: tmatch.id)

    # Ni le champ soumis ni le fond peint ne reprennent l'image du tournoi.
    # (Elle reste présente dans le JSON du select « Confrontation », qui décrit
    # les tournois rattachables et ne sert pas à la bannière.)
    hidden = response.body[/<input[^>]*name="match\[banner_image\]"[^>]*>/]
    assert_match %r{sports/ping-pong/}, hidden
    assert_no_match(/pas-du-ping-pong/, hidden)

    banner = response.body[/<div class="match-new-banner"[^>]*>/]
    assert_match %r{sports/ping-pong/}, banner
    assert_no_match(/pas-du-ping-pong/, banner)
  end

  test "POST /matches depuis un tournoi inscrit les deux joueurs et lie la carte" do
    sign_in @user
    tournament, tmatch = build_tournament_match

    assert_difference "Match.count", 1 do
      post matches_path, params: { match: {
        title: "Rencontre tournoi", date: Date.tomorrow,
        'time(4i)': "18", 'time(5i)': "00",
        players_needed: 2, level: "Tout niveau", visibility: "public",
        validation_mode: "automatic", genre_restriction: "tous",
        sport_id: @sport.id, tournament_id: tournament.id, tournament_match_id: tmatch.id
      } }
    end

    match = Match.last
    assert_equal tournament.id, match.tournament_id
    assert_equal tmatch.id, match.tournament_match_id
    # Organisateur + les 2 joueurs de la carte (le créateur n'est compté qu'une fois).
    assert_includes match.match_users.map(&:user_id), tmatch.player_b.user_id
  end

  test "GET /matches/:id affiche un rappel vers la saisie du score du tournoi" do
    sign_in @user
    tournament, tmatch = build_tournament_match
    match = Match.create!(
      title: "Rencontre tournoi", date: Date.tomorrow, time: "18:00", end_time: "19:00",
      players_needed: 2, level: "Tout niveau", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous", user: @user,
      sport: @sport, tournament: tournament, tournament_match: tmatch
    )

    get match_path(match)
    assert_response :success
    assert_select "p", text: /Score du tournoi pas encore saisi/

    tmatch.assign_score([[11, 5]])
    tmatch.save!

    get match_path(match)
    assert_response :success
    assert_select "p", text: /Score du tournoi : #{Regexp.escape(tmatch.score_summary)}/
  end

  # ── Planification par les JOUEURS (Lot 7) ───────────────────────────────────
  # Un tournoi organisé par @other_user, où @user n'est qu'un joueur inscrit.
  def build_tournament_match_as_player
    tournament = Tournament.create!(name: "Tournoi joueur", sport: @sport, user: @other_user,
                                    format: "poules", status: "in_progress", max_players: 8,
                                    date: Date.tomorrow, place: "Gymnase test")
    opponent = create_test_user(email: "opp-#{SecureRandom.hex(3)}@example.com")
    a = tournament.tournament_users.create!(user: @user, role: "joueur", status: "approved")
    b = tournament.tournament_users.create!(user: opponent, role: "joueur", status: "approved")
    round = tournament.tournament_rounds.create!(phase: "pool", number: 1, status: "in_progress")
    [tournament, round.tournament_matches.create!(player_a: a, player_b: b, position: 0)]
  end

  test "un JOUEUR (non organisateur) peut préremplir la rencontre de sa confrontation" do
    sign_in @user
    tournament, tmatch = build_tournament_match_as_player

    get new_match_path(tournament_match_id: tmatch.id)
    assert_response :success

    # Lieu et date du tournoi repris ; le titre nomme les deux adversaires.
    assert_match(/value="Gymnase test"/, response.body)
    assert_match(/value="#{tournament.date}"/, response.body)
    assert_match(/#{Regexp.escape(tmatch.player_b.display_name)}/, response.body)
    # Le tournoi apparaît dans le select : on y est inscrit, sans l'organiser.
    assert_match(/Tournoi joueur/, response.body)

    # Select « Confrontation » alimenté et présélectionné sur la carte visée.
    assert_select "select[name='match[tournament_match_id]']" do
      assert_select "option[selected][value=?]", tmatch.id.to_s
    end
  end

  test "un JOUEUR peut créer la rencontre de sa confrontation" do
    sign_in @user
    tournament, tmatch = build_tournament_match_as_player

    assert_difference "Match.count", 1 do
      post matches_path, params: { match: {
        title: "Ma rencontre de poule", date: Date.tomorrow,
        'time(4i)': "20", 'time(5i)': "30", # créneau choisi par les joueurs eux-mêmes
        players_needed: 2, level: "Tout niveau", visibility: "public",
        validation_mode: "automatic", genre_restriction: "tous",
        sport_id: @sport.id, tournament_id: tournament.id, tournament_match_id: tmatch.id
      } }
    end

    match = Match.last
    assert_equal tmatch.id, match.tournament_match_id
    assert_equal tournament.id, match.tournament_id
    assert_equal 20, match.time.hour, "l'heure choisie par le joueur est conservée"
    assert_includes match.match_users.map(&:user_id), tmatch.player_b.user_id
  end

  test "une confrontation déjà rattachée ne peut pas recevoir une 2e rencontre" do
    _tournament, tmatch = build_tournament_match_as_player
    Match.create!(title: "Déjà planifiée", date: Date.tomorrow, time: "18:00", end_time: "19:00",
                  players_needed: 2, level: "Tout niveau", visibility: "public",
                  validation_mode: "automatic", genre_restriction: "tous",
                  user: tmatch.player_b.user, sport: @sport, tournament_match: tmatch)

    sign_in @user
    post matches_path, params: { match: {
      title: "Doublon", date: Date.tomorrow,
      'time(4i)': "18", 'time(5i)': "00",
      players_needed: 2, level: "Tout niveau", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      sport_id: @sport.id, tournament_match_id: tmatch.id
    } }

    # Le lien est effacé par sanitize_tournament_link : la rencontre reste créée,
    # mais indépendante (pas de 500 sur l'index unique).
    assert_nil Match.last.tournament_match_id
  end

  test "POST /matches ignore le rattachement à un tournoi qu'on n'organise pas" do
    tournament, tmatch = build_tournament_match(owner: @other_user)
    sign_in @user # @user n'organise pas ce tournoi

    post matches_path, params: { match: {
      title: "Rencontre pirate", date: Date.tomorrow,
      'time(4i)': "18", 'time(5i)': "00",
      players_needed: 2, level: "Tout niveau", visibility: "public",
      validation_mode: "automatic", genre_restriction: "tous",
      sport_id: @sport.id, tournament_id: tournament.id, tournament_match_id: tmatch.id
    } }

    match = Match.last
    assert_nil match.tournament_id
    assert_nil match.tournament_match_id
  end
end
