require "test_helper"

# Tests de la désinscription des mails de chat (lien présent dans chaque mail).
# Route publique : c'est le token signé qui fait office d'autorisation.
class ChatEmailUnsubscribesControllerTest < ActionDispatch::IntegrationTest
  teardown { teardown_db }

  setup do
    @user  = create_test_user(email: "unsub@example.com")
    @token = @user.profil.signed_id(purpose: ChatEmailUnsubscribesController::TOKEN_PURPOSE)
  end

  test "la page de confirmation s'affiche sans être connecté, sans rien désactiver" do
    get chat_email_unsubscribe_path(token: @token)

    assert_response :success
    assert @user.profil.reload.chat_email_notifications?, "Un simple GET (antivirus mail) ne doit pas désinscrire"
  end

  test "le POST désactive les mails" do
    post chat_email_unsubscribe_path(token: @token)

    assert_response :success
    assert_not @user.profil.reload.chat_email_notifications?
  end

  test "un token falsifié renvoie une 404" do
    get chat_email_unsubscribe_path(token: "faux-token")
    assert_response :not_found

    post chat_email_unsubscribe_path(token: "faux-token")
    assert_response :not_found
  end

  test "un token signé pour un autre usage est refusé" do
    other_token = @user.profil.signed_id(purpose: :autre_chose)

    post chat_email_unsubscribe_path(token: other_token)

    assert_response :not_found
    assert @user.profil.reload.chat_email_notifications?
  end
end
