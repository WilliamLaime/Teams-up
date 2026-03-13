class NotificationsController < ApplicationController
  # GET /notifications
  # Affiche toutes les notifications de l'utilisateur connecté
  def index
    # policy_scope filtre pour ne retourner que les notifs de l'utilisateur connecté
    # Tri : non lues en premier (read: asc = false avant true), puis plus récentes en premier
    @notifications = policy_scope(Notification).order(read: :asc, created_at: :desc)
  end

  # PATCH /notifications/:id/mark_read
  # Marque une notification comme lue et redirige vers son lien
  def mark_read
    @notification = Notification.find(params[:id])
    # Pundit vérifie que la notification appartient bien à l'utilisateur connecté
    authorize @notification

    @notification.update(read: true)

    # Redirige vers le lien associé à la notification (ex: la page du match)
    redirect_to @notification.link || notifications_path
  end

  # DELETE /notifications/:id
  # Supprime une notification
  def destroy
    @notification = Notification.find(params[:id])
    authorize @notification

    @notification.destroy
    redirect_to notifications_path
  end

  # PATCH /notifications/mark_all_read
  # Marque toutes les notifications de l'utilisateur comme lues
  def mark_all_read
    # On utilise authorize avec un symbole car il n'y a pas de record unique ici
    authorize :notification, :mark_all_read?

    current_user.notifications.unread.update_all(read: true)
    redirect_to notifications_path, notice: "Toutes les notifications ont été marquées comme lues."
  end
end
