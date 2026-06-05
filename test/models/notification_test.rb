require "test_helper"

# Tests du modèle Notification.
# Une Notification appartient à un User (le destinataire) et optionnellement
# à un actor (User à l'origine de l'action, ex: celui qui envoie la demande d'ami).
# Scopes :
#   - unread  → where(read: false)
#   - recent  → order(created_at: desc)
class NotificationTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # ASSOCIATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une notification avec user et message est valide
  def test_notification_valide_avec_user
    user = create_test_user(email: "notif_user@example.com", first_name: "Notif", last_name: "User")
    notif = Notification.new(
      user:    user,
      message: "Vous avez reçu une notification.",
      read:    false
    )
    assert notif.valid?, "Une notification avec un user valide doit être valide"
  end

  # Cas nominal : l'actor est optionnel — une notification sans actor est valide
  def test_notification_valide_sans_actor
    user  = create_test_user(email: "notif_u2@example.com", first_name: "N2", last_name: "User")
    notif = Notification.new(user: user, message: "Test sans actor")
    # belongs_to :actor, optional: true → pas d'erreur si actor_id est nil
    assert notif.valid?, "Une notification sans actor doit être valide (actor est optionnel)"
  end

  # Cas nominal : une notification peut avoir un actor (autre utilisateur)
  def test_notification_valide_avec_actor
    user  = create_test_user(email: "notif_u3@example.com", first_name: "N3", last_name: "User")
    actor = create_test_user(email: "actor@example.com",    first_name: "Actor", last_name: "User")
    notif = Notification.new(
      user:     user,
      actor_id: actor.id, # actor est stocké via actor_id (integer, pas bigint FK)
      message:  "Demande d'ami de Actor"
    )
    assert notif.valid?, "Une notification avec actor doit être valide"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le scope unread retourne uniquement les notifications non lues
  def test_scope_unread_retourne_les_notifications_non_lues
    user    = create_test_user(email: "scope_u@example.com", first_name: "Scope", last_name: "User")
    n_unread = Notification.create!(user: user, message: "Non lue", read: false)
    n_read   = Notification.create!(user: user, message: "Déjà lue", read: true)

    result = Notification.unread
    # La notification non lue doit apparaître dans le scope
    assert_includes result, n_unread, "Le scope unread doit inclure les notifications non lues"
    # La notification lue ne doit pas apparaître
    assert_not_includes result, n_read, "Le scope unread ne doit pas inclure les notifications lues"
  end

  # Cas nominal : le scope recent trie les notifications de la plus récente à la plus ancienne
  def test_scope_recent_trie_du_plus_recent_au_plus_ancien
    user   = create_test_user(email: "scope_u2@example.com", first_name: "Scope2", last_name: "User")
    # Crée une vieille notification d'abord
    older  = Notification.create!(user: user, message: "Vieille", created_at: 2.days.ago, read: false)
    newer  = Notification.create!(user: user, message: "Récente", created_at: 1.day.ago,  read: false)

    result = Notification.where(user: user).recent
    # Le premier élément doit être le plus récent
    assert_equal newer.id, result.first.id,
                 "Le scope recent doit placer la notification la plus récente en premier"
  end

  # Edge case : le scope unread retourne une collection vide si toutes les notifs sont lues
  def test_scope_unread_retourne_vide_si_tout_est_lu
    user = create_test_user(email: "scope_u3@example.com", first_name: "Scope3", last_name: "User")
    Notification.create!(user: user, message: "Lue", read: true)

    result = Notification.where(user: user).unread
    assert_equal 0, result.count, "Le scope unread doit être vide si toutes les notifications sont lues"
  end
end
