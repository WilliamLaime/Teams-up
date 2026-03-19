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

    # JSON → depuis le fetch Stimulus (supprime du DOM, dropdown reste ouvert)
    # HTML → accès direct à l'URL (redirige vers la page notifications)
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to notifications_path }
    end
  end

  # PATCH /notifications/mark_all_read
  # Marque toutes les notifications de l'utilisateur comme lues
  def mark_all_read
    authorize :notification, :mark_all_read?
    current_user.notifications.unread.update_all(read: true)
    broadcast_bell_update
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to notifications_path, notice: "Toutes les notifications ont été marquées comme lues." }
    end
  end

  private

  # Met à jour la cloche dans la navbar via ActionCable pour tous les onglets ouverts.
  # Nécessaire car update_all bypasse les callbacks du modèle Notification.
  def broadcast_bell_update
    Turbo::StreamsChannel.broadcast_update_to(
      [current_user, :notifications],
      target: "notification_bell",
      partial: "shared/notification_bell",
      locals: { current_user: current_user }
    )
  end
end
