class NotificationsController < ApplicationController
  # GET /notifications
  # Affiche toutes les notifications de l'utilisateur connecté
  def index
    # Récupère toutes les notifs, les plus récentes en premier
    @notifications = current_user.notifications.recent
  end

  # PATCH /notifications/:id/mark_read
  # Marque une notification comme lue et redirige vers son lien
  def mark_read
    @notification = current_user.notifications.find(params[:id])
    @notification.update(read: true)

    # Redirige vers le lien associé à la notification (ex: la page du match)
    redirect_to @notification.link || notifications_path
  end

  # PATCH /notifications/mark_all_read
  # Marque toutes les notifications de l'utilisateur comme lues
  def mark_all_read
    current_user.notifications.unread.update_all(read: true)
    redirect_to notifications_path, notice: "Toutes les notifications ont été marquées comme lues."
  end
end
