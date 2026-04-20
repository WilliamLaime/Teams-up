# MatchReminderJob — envoie un rappel email à tous les participants approuvés
# 24h avant le début du match.
#
# Planification : enqueued à la création du match avec
#   MatchReminderJob.set(wait_until: match.build_datetime - 24.hours).perform_later(match.id)
#
# Comportement si le match n'existe plus (annulé entre-temps) :
#   → on l'ignore silencieusement (find_by retourne nil)
class MatchReminderJob < ApplicationJob
  # File "default" — pas de priorité spéciale, traitement en arrière-plan
  queue_as :default

  def perform(match_id)
    match = Match.find_by(id: match_id)

    # Le match a été supprimé entre la planification et l'exécution du job → on arrête
    return unless match

    # Sécurité : si la queue était en retard et que le match a déjà commencé,
    # on n'envoie pas le rappel (inutile et confus pour le participant)
    return if match.build_datetime <= Time.current

    # Récupère tous les participants approuvés (joueurs + organisateur)
    # includes(:user) pour éviter les N+1 queries lors de l'envoi des emails
    participants = match.match_users
                        .where(status: "approved")
                        .includes(:user)

    # Envoie un email individuel à chaque participant
    participants.each do |match_user|
      UserMailer.match_reminder(match, match_user.user).deliver_later
    end
  end
end
