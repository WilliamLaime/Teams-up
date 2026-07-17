require "test_helper"

# Tests d'intégration pour AvisController.
# Gère la création des avis (notes) entre joueurs après un match.
#   POST /users/:user_id/avis → crée l'avis si éligible
# Conditions d'éligibilité :
#   - Les deux joueurs doivent avoir participé au match (status: "approved")
#   - Le match doit être terminé et dans la fenêtre de 7 jours
#   - On ne peut pas se noter soi-même
class AvisControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @reviewer = create_test_user(email: "avis_reviewer@example.com", first_name: "Rev", last_name: "Ctrl")
    @reviewed = create_test_user(email: "avis_reviewed@example.com", first_name: "Rated", last_name: "Ctrl")

    # Crée un sport et un match terminé (il y a 2h) → dans la fenêtre de 7j
    @sport = Sport.create!(name: "Football Avis Ctrl", slug: "football_avis_ctrl", icon: "⚽")
    # On utilise save(validate: false) car le modèle interdit la création
    # d'un match dans le passé. On simule ici un match déjà terminé.
    @match = Match.new(
      title:       "Match Avis Ctrl",
      place:       "Terrain",
      date:        2.hours.ago.to_date,
      time:        2.hours.ago,
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        @reviewer,
      sport:       @sport
    )
    @match.save(validate: false)
    # Inscrit les deux joueurs comme "approved" dans le match
    MatchUser.create!(user: @reviewer, match: @match, status: "approved", role: "joueur")
    MatchUser.create!(user: @reviewed, match: @match, status: "approved", role: "joueur")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /users/:user_id/avis — créer un avis
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : crée l'avis et redirige vers le profil du joueur noté
  def test_post_avis_cree_lavis_et_redirige
    sign_in @reviewer
    assert_difference "Avis.count", 1 do
      post user_avis_path(@reviewed), params: {
        avis: {
          match_id: @match.id,
          rating:   4,
          content:  "Excellent joueur !"
        }
      }
    end
    # Après une création réussie, on est redirigé vers le profil du joueur noté
    assert_redirected_to user_profil_path(@reviewed),
                         "POST /users/:id/avis doit rediriger vers le profil du joueur noté"
    assert_not_nil flash[:notice], "Un flash notice doit être présent après succès"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_post_avis_redirige_si_non_connecte
    assert_no_difference "Avis.count" do
      post user_avis_path(@reviewed), params: {
        avis: { match_id: @match.id, rating: 4 }
      }
    end
    assert_response :redirect, "Un visiteur non connecté doit être redirigé"
  end

  # Cas d'erreur : une note invalide (ex: 0) → l'avis n'est pas créé, flash alert
  def test_post_avis_echoue_avec_note_invalide
    sign_in @reviewer
    assert_no_difference "Avis.count" do
      post user_avis_path(@reviewed), params: {
        avis: { match_id: @match.id, rating: 0 } # 0 est hors de la plage 1-5
      }
    end
    # La validation du modèle échoue → flash alert avec le message d'erreur
    assert_redirected_to user_profil_path(@reviewed)
    assert_not_nil flash[:alert], "Un flash alert doit être présent si la note est invalide"
  end

  # Cas d'erreur : Pundit bloque si on essaie de se noter soi-même
  def test_post_avis_interdit_de_se_noter_soi_meme
    sign_in @reviewer
    assert_no_difference "Avis.count" do
      # @reviewer essaie de se noter lui-même
      post user_avis_path(@reviewer), params: {
        avis: { match_id: @match.id, rating: 5 }
      }
    end
    # Pundit (AvisPolicy#create?) bloque → redirection avec alert
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end
end
