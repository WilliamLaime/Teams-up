require "test_helper"

# Tests d'intégration pour NotificationsController.
# Gère les notifications in-app de l'utilisateur :
#   GET   /notifications                   → liste (index)
#   PATCH /notifications/:id/mark_read     → marquer une notif comme lue
#   DELETE /notifications/:id              → supprimer une notif
#   PATCH /notifications/mark_all_read     → tout marquer comme lu
class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @user  = create_test_user(email: "notif_ctrl@example.com", first_name: "Notif", last_name: "Ctrl")
    @other = create_test_user(email: "notif_other@example.com", first_name: "Other", last_name: "Notif")
    # Crée deux notifications pour @user
    @notif_unread = Notification.create!(user: @user, message: "Non lue", read: false)
    @notif_read   = Notification.create!(user: @user, message: "Déjà lue", read: true)
    # Une notification appartenant à @other (ne doit pas être accessible par @user)
    @other_notif  = Notification.create!(user: @other, message: "Notif autre user", read: false)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /notifications — index
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur connecté peut voir ses notifications (200 OK)
  def test_get_notifications_retourne_200_si_connecte
    sign_in @user
    get notifications_path
    assert_response :success, "GET /notifications doit retourner 200 pour un utilisateur connecté"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_get_notifications_redirige_si_non_connecte
    get notifications_path
    assert_response :redirect, "GET /notifications doit rediriger un visiteur non connecté"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /notifications/:id/mark_read — marquer une notif comme lue
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : marque la notification comme lue et redirige vers son lien
  def test_patch_mark_read_marque_la_notif_comme_lue
    sign_in @user
    patch mark_read_notification_path(@notif_unread)
    # La notification doit maintenant être marquée comme lue
    assert @notif_unread.reload.read, "La notification doit être marquée comme lue"
    # Redirigé vers le lien de la notification (nil → notifications_path)
    assert_redirected_to notifications_path
  end

  # Cas d'erreur : Pundit empêche de marquer la notif d'un autre utilisateur
  def test_patch_mark_read_interdit_pour_notif_dun_autre_user
    sign_in @user
    # @user essaie de marquer la notification de @other → Pundit doit bloquer
    patch mark_read_notification_path(@other_notif)
    # Pundit lève NotAuthorizedError → redirection avec alert
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert Pundit doit être présent"
    # La notification de @other ne doit pas être marquée comme lue
    refute @other_notif.reload.read, "La notification de @other ne doit pas être modifiée"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /notifications/:id — supprimer une notif
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : supprime la notification et redirige vers la liste
  def test_delete_notification_supprime_et_redirige
    sign_in @user
    assert_difference "Notification.count", -1 do
      delete notification_path(@notif_unread)
    end
    assert_redirected_to notifications_path, "DELETE doit rediriger vers /notifications"
  end

  # Cas d'erreur : Pundit empêche de supprimer la notif d'un autre utilisateur
  def test_delete_notification_interdit_pour_notif_dun_autre_user
    sign_in @user
    assert_no_difference "Notification.count" do
      delete notification_path(@other_notif)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert Pundit doit être présent"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /notifications/mark_all_read — tout marquer comme lu
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : toutes les notifications non lues de l'user sont marquées lues
  def test_patch_mark_all_read_marque_toutes_les_notifs_comme_lues
    sign_in @user
    patch mark_all_read_notifications_path, as: :json
    assert_response :success, "PATCH /notifications/mark_all_read doit retourner 200"
    # Toutes les notifications de @user doivent être lues
    assert_equal 0, @user.notifications.unread.count,
                 "Toutes les notifications de @user doivent être marquées comme lues"
    # La notification de @other ne doit pas être modifiée
    assert @other_notif.reload.read == false,
           "La notification de @other ne doit pas être affectée"
  end

  # Cas d'erreur : un visiteur non connecté ne peut pas appeler mark_all_read
  def test_patch_mark_all_read_redirige_si_non_connecte
    patch mark_all_read_notifications_path, as: :json
    assert_response :redirect, "mark_all_read doit rediriger un visiteur non connecté"
  end
end
