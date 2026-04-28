# Purge périodique des SecurityLog anciens.
# Politique de rétention :
#   - rack_attack_throttle : 30 jours (fort volume, utilité court-terme)
#   - autres event_types   : 90 jours (valeur d'audit plus longue)
class SecurityLogCleanupJob < ApplicationJob
  queue_as :default

  THROTTLE_RETENTION  = 30.days
  DEFAULT_RETENTION   = 90.days
  BATCH_SIZE          = 1_000 # limite l'impact sur la DB par itération

  def perform
    delete_in_batches("rack_attack_throttle", THROTTLE_RETENTION)
    delete_in_batches_except("rack_attack_throttle", DEFAULT_RETENTION)
  end

  private

  # Supprime les logs d'un type d'événement spécifique par lots de BATCH_SIZE
  # pour éviter de charger la base de données en mémoire.
  def delete_in_batches(event_type, retention)
    cutoff = retention.ago
    loop do
      deleted = SecurityLog
                  .where(event_type: event_type)
                  .where("created_at < ?", cutoff)
                  .limit(BATCH_SIZE)
                  .delete_all
      break if deleted < BATCH_SIZE
    end
  end

  # Supprime tous les autres types d'événements (excluant le type passé).
  def delete_in_batches_except(excluded_type, retention)
    cutoff = retention.ago
    loop do
      deleted = SecurityLog
                  .where.not(event_type: excluded_type)
                  .where("created_at < ?", cutoff)
                  .limit(BATCH_SIZE)
                  .delete_all
      break if deleted < BATCH_SIZE
    end
  end
end
