class NotificationsController < ApplicationController
  # GET /notifications
  # Affiche toutes les notifications de l'utilisateur connecté
  def index
    # policy_scope filtre pour ne retourner que les notifs de l'utilisateur connecté
    @notifications = policy_scope(Notification).order(created_at: :desc)
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
  # Supprime une notification sans naviguer (Turbo Stream)
  def destroy
    @notification = Notification.find(params[:id])
    # Pundit vérifie que la notification appartient bien à l'utilisateur connecté
    authorize @notification

    @notification.destroy

    # Turbo Stream : supprime l'élément du DOM sans recharger la page
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  # PATCH /notifications/mark_all_read
  # Marque toutes les notifications de l'utilisateur comme lues
  def mark_all_read
    # On utilise authorize avec un symbole car il n'y a pas de record unique ici
    authorize :notification, :mark_all_read?

    current_user.notifications.unread.update_all(read: true)

    # On recharge les notifications (toutes lues maintenant) pour le Turbo Stream
    @notifications = policy_scope(Notification).order(created_at: :desc)

    # Turbo Stream : met à jour le DOM sans recharger la page
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to notifications_path, notice: "Toutes les notifications ont été marquées comme lues." }
    end
  end
end
