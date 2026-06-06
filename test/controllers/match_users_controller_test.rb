# Tests d'intégration pour MatchUsersController
# Vérifie les inscriptions aux matchs : rejoindre, quitter, approuver, rejeter, confirmer
require "test_helper"

class MatchUsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ──────────────────────────────────────────────────────────────────
  setup do
    # Organisateur du match.
    # create_test_user crée le User + le Profil en une seule opération.
    # Sans ça, User.create! sans first_name/last_name échoue (validés on: :create).
    @organizer = create_test_user(
      email:      "organizer_mu@example.com",
      first_name: "Orga",
      last_name:  "Test"
    )

    # Joueur qui va tenter de rejoindre le match
    @player = create_test_user(
      email:      "player_mu@example.com",
      first_name: "Joueur",
      last_name:  "Test"
    )

    # Deuxième joueur pour tester les conflits
    @player2 = create_test_user(
      email:      "player2_mu@example.com",
      first_name: "Joueur2",
      last_name:  "Test"
    )

    # Joueuse (pour les tests de restriction de genre)
    @female_player = create_test_user(
      email:      "female_mu@example.com",
      first_name: "Julie",
      last_name:  "Test"
    )
    # On met à jour le genre séparément car create_test_user ne le gère pas
    @female_player.update_column(:genre, "femme")

    # Sport nécessaire pour créer le match
    @sport = Sport.create!(name: "Basketball MU", slug: "basketball-mu", icon: "🏀")

    # Match en mode automatique avec des places disponibles
    @match = Match.create!(
      title: "Match MatchUsers Test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      player_left: 4,
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @organizer,
      sport: @sport
    )
    # L'organisateur est inscrit comme organisateur approuvé
    @organizer_match_user = @match.match_users.create!(
      user: @organizer, role: "organisateur", status: "approved"
    )

    # Match en mode manuel (validation par l'organisateur)
    @manual_match = Match.create!(
      title: "Match Manuel Test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 20, min: 0),
      player_left: 3,
      level: "Débutant",
      visibility: "public",
      validation_mode: "manual",
      genre_restriction: "tous",
      user: @organizer,
      sport: @sport
    )
    @manual_match.match_users.create!(
      user: @organizer, role: "organisateur", status: "approved"
    )

    # Match complet (0 places restantes).
    # player_left: 0 est invalide (validates: >= 1), donc on crée avec 1
    # puis on force 0 en base via update_column (bypass validations).
    @full_match = Match.create!(
      title: "Match Complet Test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 21, min: 0),
      player_left: 1,  # valeur minimale valide
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @organizer,
      sport: @sport
    )
    # On passe à 0 en bypassant les validations pour simuler un match sans place
    @full_match.update_column(:player_left, 0)
    @full_match.match_users.create!(
      user: @organizer, role: "organisateur", status: "approved"
    )

    # Match réservé aux femmes
    @female_match = Match.create!(
      title: "Match Féminin Test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 22, min: 0),
      player_left: 4,
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "feminin",
      user: @organizer,
      sport: @sport
    )
    @female_match.match_users.create!(
      user: @organizer, role: "organisateur", status: "approved"
    )
  end

  # ─── teardown : nettoyage complet dans l'ordre FK ───────────────────────────
  # teardown_db supprime toutes les tables dans le bon ordre pour éviter les
  # violations FK (Friendship, TeamMember, etc. referent les Users).
  teardown do
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /matches/:match_id/match_users — rejoindre un match
  # ════════════════════════════════════════════════════════════════════════════

  # Visiteur non connecté → Devise redirige vers la page de login
  test "POST /matches/:match_id/match_users redirige vers login si non connecté" do
    post match_match_users_path(@match)
    assert_redirected_to new_user_session_path
  end

  # Cas nominal (mode automatique) : inscription "approved" immédiatement
  test "POST crée une inscription approved si mode automatique et place disponible" do
    sign_in @player
    assert_difference "MatchUser.count", 1 do
      post match_match_users_path(@match)
    end
    # Le joueur doit être approuvé immédiatement en mode automatique
    mu = @match.match_users.find_by(user: @player)
    assert_equal "approved", mu.status
    assert_redirected_to match_path(@match)
  end

  # Cas nominal (mode manuel) : inscription "pending" en attente de validation
  test "POST crée une inscription pending si mode validation manuelle" do
    sign_in @player
    assert_difference "MatchUser.count", 1 do
      post match_match_users_path(@manual_match)
    end
    mu = @manual_match.match_users.find_by(user: @player)
    # En mode manuel, le joueur attend la validation de l'organisateur
    assert_equal "pending", mu.status
    assert_redirected_to match_path(@manual_match)
  end

  # Cas limite (match complet) : inscription "waiting" en file d'attente
  test "POST crée une inscription waiting si match complet" do
    sign_in @player
    assert_difference "MatchUser.count", 1 do
      post match_match_users_path(@full_match)
    end
    mu = @full_match.match_users.find_by(user: @player)
    # Aucune place → file d'attente
    assert_equal "waiting", mu.status
  end

  # Cas d'erreur : user déjà inscrit → redirige avec alert
  test "POST redirige avec alert si user déjà inscrit" do
    sign_in @player
    # Première inscription réussie
    @match.match_users.create!(user: @player, role: "joueur", status: "approved")

    # Deuxième tentative d'inscription
    assert_no_difference "MatchUser.count" do
      post match_match_users_path(@match)
    end
    assert_redirected_to match_path(@match)
    assert_not_nil flash[:alert]
  end

  # Cas d'erreur (genre) : un homme ne peut pas rejoindre un match féminin
  test "POST redirige avec alert si match feminin et user non-femme" do
    sign_in @player  # @player n'a pas de genre = pas femme
    assert_no_difference "MatchUser.count" do
      post match_match_users_path(@female_match)
    end
    assert_not_nil flash[:alert]
  end

  # Cas limite : une femme peut bien rejoindre un match féminin
  test "POST crée l'inscription si match feminin et user femme" do
    sign_in @female_player
    assert_difference "MatchUser.count", 1 do
      post match_match_users_path(@female_match)
    end
    assert_redirected_to match_path(@female_match)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /matches/:match_id/match_users/:id — quitter un match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le joueur peut quitter le match (supprime son inscription)
  test "DELETE supprime l'inscription si propriétaire du MatchUser" do
    sign_in @player
    mu = @match.match_users.create!(user: @player, role: "joueur", status: "approved")
    @match.decrement!(:player_left)

    assert_difference "MatchUser.count", -1 do
      delete match_match_user_path(@match, mu)
    end
    assert_redirected_to match_path(@match)
  end

  # Cas d'erreur Pundit : un autre user ne peut pas supprimer l'inscription d'autrui
  test "DELETE redirige avec alert si tentative de supprimer l'inscription d'un autre" do
    # @player2 essaie de supprimer l'inscription de @player
    mu = @match.match_users.create!(user: @player, role: "joueur", status: "pending")
    sign_in @player2

    assert_no_difference "MatchUser.count" do
      delete match_match_user_path(@match, mu)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:match_id/match_users/:id/approve — approuver un joueur
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut approuver un joueur pending
  test "PATCH /approve approuve le joueur si organisateur" do
    sign_in @organizer
    mu = @manual_match.match_users.create!(user: @player, role: "joueur", status: "pending")

    patch approve_match_match_user_path(@manual_match, mu)
    # Après approbation, le statut passe à "approved"
    assert_equal "approved", mu.reload.status
  end

  # Cas d'erreur Pundit : un joueur lambda ne peut pas approuver
  test "PATCH /approve redirige avec alert pour un non-organisateur" do
    sign_in @player
    mu = @manual_match.match_users.create!(user: @player2, role: "joueur", status: "pending")

    patch approve_match_match_user_path(@manual_match, mu)
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # Cas limite (idempotence) : approuver un joueur déjà approuvé redirige sans erreur
  test "PATCH /approve redirige vers le match si joueur déjà approuvé" do
    sign_in @organizer
    mu = @match.match_users.create!(user: @player, role: "joueur", status: "approved")

    # Le joueur est déjà approuvé — la garde idempotente doit simplement rediriger
    patch approve_match_match_user_path(@match, mu)
    assert_redirected_to match_path(@match)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:match_id/match_users/:id/reject — rejeter un joueur
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut rejeter un joueur pending
  test "PATCH /reject rejette le joueur si organisateur" do
    sign_in @organizer
    mu = @manual_match.match_users.create!(user: @player, role: "joueur", status: "pending")

    patch reject_match_match_user_path(@manual_match, mu)
    assert_equal "rejected", mu.reload.status
  end

  # Cas d'erreur Pundit : un joueur lambda ne peut pas rejeter
  test "PATCH /reject redirige avec alert pour un non-organisateur" do
    sign_in @player
    mu = @manual_match.match_users.create!(user: @player2, role: "joueur", status: "pending")

    patch reject_match_match_user_path(@manual_match, mu)
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:match_id/match_users/:id/confirm — confirmer sa participation
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un membre d'équipe peut confirmer sa participation
  test "PATCH /confirm confirme la participation si c'est l'user concerné et match d'équipe" do
    # Crée une équipe et un match d'équipe
    team = Team.create!(name: "Équipe Confirm Test", captain: @organizer)
    team_match = Match.create!(
      title: "Match Équipe Confirm",
      date: Date.tomorrow,
      time: Time.current.change(hour: 17, min: 0),
      player_left: 3,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @organizer,
      sport: @sport,
      team: team
    )
    # @player est en pending dans ce match d'équipe
    mu = team_match.match_users.create!(user: @player, role: "joueur", status: "pending")

    sign_in @player
    patch confirm_match_match_user_path(team_match, mu)
    # Le statut doit passer à "approved" après confirmation
    assert_equal "approved", mu.reload.status
    assert_redirected_to match_path(team_match)
  ensure
    MatchUser.where(match: team_match).delete_all if team_match
    team_match&.destroy
    team&.destroy
  end

  # Cas d'erreur : match non-équipe → redirige avec alert
  test "PATCH /confirm redirige avec alert si match non-équipe" do
    sign_in @player
    mu = @match.match_users.create!(user: @player, role: "joueur", status: "pending")

    patch confirm_match_match_user_path(@match, mu)
    # @match n'a pas de team_id → erreur
    assert_redirected_to match_path(@match)
    assert_not_nil flash[:alert]
  end
end
