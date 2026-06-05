require "test_helper"

# Tests de NotificationPolicy — vérifie les règles d'autorisation sur les notifications.
#
# Règles testées :
#   mark_read?     → uniquement le propriétaire de la notification
#   destroy?       → uniquement le propriétaire de la notification
#   mark_all_read? → tout utilisateur connecté (retourne toujours true)
#   Scope#resolve  → ne retourne que les notifications de l'utilisateur connecté
class NotificationPolicyTest < ActiveSupport::TestCase
  def setup
    @owner = users(:one)  # propriétaire de la notification
    @other = users(:two)  # autre utilisateur

    # Notification appartenant à @owner
    @notification_owner = notifications(:unread_for_one)
    # Notification appartenant à @other
    @notification_other = notifications(:read_for_two)
  end

  # ── mark_read? ────────────────────────────────────────────────────────────

  # Le propriétaire peut marquer sa notification comme lue
  def test_mark_read_autorise_pour_le_proprietaire
    assert NotificationPolicy.new(@owner, @notification_owner).mark_read?,
           "Le propriétaire doit pouvoir marquer sa notification comme lue"
  end

  # Un autre utilisateur ne peut pas marquer la notification d'autrui comme lue
  def test_mark_read_interdit_pour_un_autre_utilisateur
    refute NotificationPolicy.new(@other, @notification_owner).mark_read?,
           "Un autre utilisateur ne doit pas pouvoir marquer la notification d'autrui"
  end

  # ── destroy? ──────────────────────────────────────────────────────────────

  # Le propriétaire peut supprimer sa propre notification
  def test_destroy_autorise_pour_le_proprietaire
    assert NotificationPolicy.new(@owner, @notification_owner).destroy?,
           "Le propriétaire doit pouvoir supprimer sa propre notification"
  end

  # Un autre utilisateur ne peut pas supprimer la notification de quelqu'un d'autre
  def test_destroy_interdit_pour_un_autre_utilisateur
    refute NotificationPolicy.new(@other, @notification_owner).destroy?,
           "Un autre utilisateur ne doit pas pouvoir supprimer la notification d'autrui"
  end

  # ── mark_all_read? ────────────────────────────────────────────────────────

  # Tout utilisateur connecté peut marquer toutes ses notifications comme lues
  # (la policy retourne toujours true — le controller filtre par current_user)
  def test_mark_all_read_autorise_pour_tout_utilisateur
    assert NotificationPolicy.new(@owner, @notification_owner).mark_all_read?,
           "Tout utilisateur connecté doit pouvoir marquer toutes ses notifs comme lues"
  end

  def test_mark_all_read_autorise_pour_autre_utilisateur
    assert NotificationPolicy.new(@other, @notification_other).mark_all_read?,
           "mark_all_read? doit retourner true pour tout utilisateur connecté"
  end

  # ── Scope#resolve ─────────────────────────────────────────────────────────

  # Le scope ne retourne que les notifications appartenant à l'utilisateur connecté
  def test_scope_retourne_uniquement_les_notifications_de_l_utilisateur
    resolved = NotificationPolicy::Scope.new(@owner, Notification.all).resolve

    # La notification de @owner doit être incluse
    assert_includes resolved, @notification_owner,
                    "Le scope doit inclure les notifications de l'utilisateur connecté"

    # La notification de @other ne doit PAS être incluse
    refute_includes resolved, @notification_other,
                    "Le scope ne doit pas inclure les notifications d'un autre utilisateur"
  end

  # Le scope de @other ne contient que ses propres notifications
  def test_scope_separe_bien_les_notifications_entre_utilisateurs
    resolved_other = NotificationPolicy::Scope.new(@other, Notification.all).resolve

    assert_includes resolved_other, @notification_other,
                    "Le scope de @other doit inclure sa propre notification"
    refute_includes resolved_other, @notification_owner,
                    "Le scope de @other ne doit pas inclure la notification de @owner"
  end
end
