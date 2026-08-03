# Purge des journaux de sécurité dont la durée de conservation est dépassée.
#
# Pourquoi cette tâche existe : un SecurityLog contient une adresse IP et un
# user-agent, donc des données personnelles. Le RGPD exige une durée de
# conservation définie *et appliquée* — une table de journaux qui grossit
# indéfiniment est une non-conformité en soi (voir docs/SECURITE-RGPD.md).
#
# Utilisation :
#   rake security_logs:purge              # applique SecurityLog::RETENTION_PERIOD (12 mois)
#   rake security_logs:purge MONTHS=6     # force une autre durée
#   rake security_logs:purge DRY_RUN=1    # compte sans supprimer
#
# À planifier une fois par jour ou par semaine côté hébergeur (cron / scheduler).
namespace :security_logs do
  desc "Supprime les SecurityLog plus vieux que la durée de conservation (12 mois par défaut)"
  task purge: :environment do
    months  = ENV["MONTHS"].presence&.to_i
    period  = months ? months.months : SecurityLog::RETENTION_PERIOD
    dry_run = ENV["DRY_RUN"].present?

    scope = SecurityLog.purgeable(period)
    count = scope.count

    if count.zero?
      puts "✅ Aucun journal à purger (rétention : #{period.inspect})."
      next
    end

    if dry_run
      puts "🔍 DRY_RUN — #{count} journal(aux) seraient supprimés (antérieurs au #{period.ago.to_date})."
      next
    end

    # delete_all plutôt que destroy_all : pas de callback ni d'association à
    # cascader sur ce modèle, et on peut avoir beaucoup de lignes à supprimer.
    deleted = scope.delete_all
    puts "🧹 #{deleted} journal(aux) supprimés (antérieurs au #{period.ago.to_date}, rétention #{period.inspect})."
  end
end
