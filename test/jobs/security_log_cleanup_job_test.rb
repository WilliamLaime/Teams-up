require "test_helper"

# Tests pour SecurityLogCleanupJob
# Ce job supprime les logs de sécurité anciens selon leur type :
#   - rack_attack_throttle : conservé 30 jours
#   - autres types         : conservés 90 jours
# Les logs récents (dans la fenêtre de rétention) doivent être préservés.
class SecurityLogCleanupJobTest < ActiveJob::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  teardown do
    # Nettoyage manuel des security_logs (pas inclus dans teardown_db standard)
    SecurityLog.delete_all
    teardown_db
  end

  # Helper privé pour créer un SecurityLog facilement
  # @param event_type [String] type d'événement
  # @param created_at [Time]   date de création (pour simuler des logs anciens)
  def create_security_log(event_type:, created_at:)
    SecurityLog.create!(
      event_type: event_type,
      ip_address: "127.0.0.1",
      created_at: created_at,
      updated_at: created_at
    )
  end

  # ── CAS NOMINAL : SUPPRESSION DES LOGS RACK_ATTACK ANCIENS ───────────────────

  # Vérifie que les logs "rack_attack_throttle" de plus de 30 jours sont supprimés.
  # Les logs "rack_attack_throttle" récents (< 30j) doivent être conservés.
  test "supprime les logs rack_attack_throttle de plus de 30 jours" do
    # Log à supprimer : créé il y a 31 jours (hors fenêtre de 30 jours)
    old_log = create_security_log(
      event_type: "rack_attack_throttle",
      created_at: 31.days.ago
    )
    # Log à conserver : créé il y a 10 jours (dans la fenêtre de 30 jours)
    recent_log = create_security_log(
      event_type: "rack_attack_throttle",
      created_at: 10.days.ago
    )

    SecurityLogCleanupJob.perform_now

    # Le vieux log doit avoir été supprimé
    assert_nil SecurityLog.find_by(id: old_log.id),
               "Le log rack_attack_throttle ancien doit avoir été supprimé"

    # Le log récent doit toujours exister
    assert SecurityLog.exists?(id: recent_log.id),
           "Le log rack_attack_throttle récent doit être conservé"
  end

  # ── CAS NOMINAL : SUPPRESSION DES AUTRES LOGS ANCIENS ───────────────────────

  # Vérifie que les logs d'autres types (ex: "login_failure") de plus de 90 jours
  # sont supprimés. Les logs récents (< 90j) doivent être conservés.
  # On utilise "login_failure" car c'est un event_type valide selon SecurityLog::EVENT_TYPES.
  test "supprime les autres logs de plus de 90 jours" do
    # Log à supprimer : créé il y a 91 jours
    old_log = create_security_log(
      event_type: "login_failure",
      created_at: 91.days.ago
    )
    # Log à conserver : créé il y a 30 jours (dans la fenêtre de 90 jours)
    recent_log = create_security_log(
      event_type: "login_failure",
      created_at: 30.days.ago
    )

    SecurityLogCleanupJob.perform_now

    # Le vieux log "login_failure" doit avoir été supprimé
    assert_nil SecurityLog.find_by(id: old_log.id),
               "Le log login_failure ancien doit avoir été supprimé"

    # Le log récent doit toujours exister
    assert SecurityLog.exists?(id: recent_log.id),
           "Le log login_failure récent doit être conservé"
  end

  # ── CAS LIMITE : AUCUN LOG À SUPPRIMER ──────────────────────────────────────

  # Vérifie que le job s'exécute sans erreur quand il n'y a aucun log à supprimer
  # (tous les logs sont récents ou la base est vide).
  test "ne plante pas si aucun log à supprimer" do
    # Log rack_attack récent (< 30j) — ne doit PAS être supprimé
    create_security_log(event_type: "rack_attack_throttle", created_at: 5.days.ago)
    # Log login_success récent (< 90j) — ne doit PAS être supprimé
    # "login_success" est un event_type valide selon SecurityLog::EVENT_TYPES
    create_security_log(event_type: "login_success", created_at: 45.days.ago)

    count_before = SecurityLog.count

    assert_nothing_raised do
      SecurityLogCleanupJob.perform_now
    end

    # Aucun log ne doit avoir été supprimé
    assert_equal count_before, SecurityLog.count,
                 "Aucun log récent ne doit avoir été supprimé"
  end

  # ── CAS LIMITE : BASE VIDE ────────────────────────────────────────────────────

  # Vérifie que le job s'exécute sans erreur si la table security_logs est vide.
  test "ne plante pas si la table security_logs est vide" do
    SecurityLog.delete_all

    assert_nothing_raised do
      SecurityLogCleanupJob.perform_now
    end

    assert_equal 0, SecurityLog.count
  end

  # ── CAS LIMITE : RESPECT DES POLITIQUES DE RÉTENTION DIFFÉRENTES ─────────────

  # Vérifie que les politiques de rétention sont bien distinctes :
  # un log "rack_attack_throttle" de 45 jours doit être supprimé (> 30j),
  # mais un log "failed_login" de 45 jours doit être conservé (< 90j).
  test "applique des politiques de rétention distinctes selon le type" do
    # Log rack_attack à 45 jours → au-delà des 30 jours → doit être supprimé
    throttle_log = create_security_log(
      event_type: "rack_attack_throttle",
      created_at: 45.days.ago
    )
    # Log login_failure à 45 jours → encore dans les 90 jours → doit être conservé
    # "login_failure" est un event_type valide selon SecurityLog::EVENT_TYPES
    login_log = create_security_log(
      event_type: "login_failure",
      created_at: 45.days.ago
    )

    SecurityLogCleanupJob.perform_now

    assert_nil SecurityLog.find_by(id: throttle_log.id),
               "Le log rack_attack à 45j doit être supprimé (rétention 30j)"

    assert SecurityLog.exists?(id: login_log.id),
           "Le log login_failure à 45j doit être conservé (rétention 90j)"
  end
end
