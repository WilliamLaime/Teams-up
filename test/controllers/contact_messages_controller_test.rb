require "test_helper"

# Tests d'intégration pour ContactMessagesController.
# IMPORTANT : ce controller est "semi-public" — il fait skip_before_action :authenticate_user!
# MAIS le before_action :redirect_to_landing_if_visitor reste actif dans ApplicationController.
# Résultat : les visiteurs NON connectés sont redirigés vers root_path (landing).
# Les tests doivent donc utiliser sign_in pour accéder au formulaire.
#
# POST /contact → crée un ContactMessage si les paramètres sont valides
# Note ValidEmail2 : example.com n'a PAS de MX record → on utilise gmail.com.
class ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  # Un utilisateur connecté pour contourner redirect_to_landing_if_visitor
  def setup
    @user = create_test_user(email: "contact_tester@example.com", first_name: "Con", last_name: "Tact")
  end

  # Attributs valides pour le formulaire de contact.
  # gmail.com a un MX record réel → valid_mx? retourne true.
  CTRL_VALID_PARAMS = {
    contact_message: {
      prenom:  "Alice",
      nom:     "Martin",
      email:   "alice@gmail.com",
      sujet:   "Test question",
      message: "Bonjour, ceci est un test."
    }
  }.freeze

  # ════════════════════════════════════════════════════════════════════════════
  # POST /contact — créer un message de contact
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un message valide est créé et redirige vers /contact avec notice.
  # Un utilisateur connecté est nécessaire car redirect_to_landing_if_visitor
  # bloque les visiteurs non connectés.
  def test_post_contact_cree_le_message_et_redirige
    sign_in @user # nécessaire pour passer redirect_to_landing_if_visitor
    assert_difference "ContactMessage.count", 1 do
      post contact_path, params: CTRL_VALID_PARAMS
    end
    # Après succès, on est redirigé vers la page de contact
    assert_redirected_to contact_path,
                         "POST /contact doit rediriger vers /contact après succès"
    assert_not_nil flash[:notice], "Un flash notice doit être présent"
  end

  # Cas nominal : redirect_to_landing_if_visitor redirige les visiteurs non connectés
  # vers root_path (pas vers new_user_session_path qui serait Devise)
  def test_post_contact_redirige_visiteur_vers_landing
    # Envoie sans sign_in → redirect_to_landing_if_visitor redirige vers root_path
    post contact_path, params: CTRL_VALID_PARAMS
    # Le visiteur est redirigé, PAS vers Devise (/users/sign_in) mais vers la landing
    assert_response :redirect,
                    "Un visiteur non connecté doit être redirigé (vers la landing)"
    assert_not_equal new_user_session_path, response.location,
                     "La redirection ne doit pas aller vers la page de login Devise"
  end

  # Cas d'erreur : un prénom manquant → 422 Unprocessable Entity
  def test_post_contact_echoue_si_prenom_manquant
    sign_in @user
    params = CTRL_VALID_PARAMS.deep_merge(contact_message: { prenom: nil })
    assert_no_difference "ContactMessage.count" do
      post contact_path, params: params
    end
    # Le controller réaffiche le formulaire avec le statut 422
    assert_response :unprocessable_entity,
                    "POST /contact avec un prénom manquant doit retourner 422"
  end

  # Cas d'erreur : un email mal formaté → 422 Unprocessable Entity
  def test_post_contact_echoue_si_email_invalide
    sign_in @user
    params = CTRL_VALID_PARAMS.deep_merge(contact_message: { email: "pas-un-email" })
    assert_no_difference "ContactMessage.count" do
      post contact_path, params: params
    end
    assert_response :unprocessable_entity,
                    "POST /contact avec un email invalide doit retourner 422"
  end

  # Cas d'erreur : tous les champs vides (nil) → 422 Unprocessable Entity.
  # On passe des valeurs nil plutôt qu'un hash vide {} pour éviter
  # ActionController::ParameterMissing (400) qui est levé quand `require(:contact_message)`
  # ne trouve pas la clé dans params — le hash vide provoque un 400, pas un 422.
  def test_post_contact_echoue_si_tous_les_champs_vides
    sign_in @user
    assert_no_difference "ContactMessage.count" do
      post contact_path, params: {
        contact_message: { prenom: nil, nom: nil, email: nil, sujet: nil, message: nil }
      }
    end
    # Quand les champs sont nil, les validations échouent → 422 Unprocessable Entity
    assert_response :unprocessable_entity,
                    "POST /contact avec tous les champs nil doit retourner 422"
  end
end
