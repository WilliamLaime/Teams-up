class FriendshipsController < ApplicationController
  # POST /users/:user_id/friendship
  # Envoie une demande d'ami à l'utilisateur ciblé
  def create
    @friend = User.find(params[:user_id])

    # Empêche de s'envoyer une demande à soi-même
    if current_user == @friend
      redirect_back fallback_location: profil_path, alert: "Vous ne pouvez pas vous ajouter vous-même."
      return
    end

    # Si on est déjà amis (demande acceptée), on ne fait rien
    if current_user.friends_with?(@friend)
      redirect_back fallback_location: user_profil_path(@friend), alert: "Vous êtes déjà amis avec #{@friend.display_name}."
      return
    end

    # Si une demande est déjà en attente dans ce sens, on ne la recrée pas
    if current_user.pending_request_sent_to?(@friend)
      redirect_back fallback_location: user_profil_path(@friend), alert: "Une demande est déjà en attente."
      return
    end

    # Crée la demande avec statut "pending"
    @friendship = current_user.friendships.new(friend: @friend, status: "pending")
    authorize @friendship

    if @friendship.save
      # Envoie une notification au destinataire
      Notification.create(
        user:    @friend,
        message: "👋 #{current_user.display_name} vous a envoyé une demande d'ami.",
        link:    user_profil_path(current_user)
      )
      redirect_back fallback_location: user_profil_path(@friend),
                    notice: "Demande d'ami envoyée à #{@friend.display_name} !"
    else
      redirect_back fallback_location: user_profil_path(@friend), alert: "Impossible d'envoyer la demande."
    end
  end

  # PATCH /users/:user_id/friendship/accept
  # Accepte la demande d'ami envoyée par l'utilisateur ciblé
  def accept
    @sender = User.find(params[:user_id])

    # Retrouve la demande en attente envoyée par @sender à current_user
    @friendship = current_user.pending_friendship_from(@sender)

    if @friendship.nil?
      redirect_back fallback_location: profil_path, alert: "Aucune demande en attente de cet utilisateur."
      return
    end

    authorize @friendship

    # Passe le statut à "accepted"
    @friendship.update!(status: "accepted")

    # Notifie l'expéditeur que sa demande a été acceptée
    Notification.create(
      user:    @sender,
      message: "🎉 #{current_user.display_name} a accepté votre demande d'ami !",
      link:    user_profil_path(current_user)
    )

    redirect_back fallback_location: profil_path,
                  notice: "Vous êtes maintenant amis avec #{@sender.display_name} !"
  end

  # PATCH /users/:user_id/friendship/decline
  # Refuse la demande d'ami envoyée par l'utilisateur ciblé
  def decline
    @sender = User.find(params[:user_id])

    # Retrouve la demande en attente envoyée par @sender à current_user
    @friendship = current_user.pending_friendship_from(@sender)

    if @friendship.nil?
      redirect_back fallback_location: profil_path, alert: "Aucune demande en attente de cet utilisateur."
      return
    end

    authorize @friendship

    # Supprime la demande (on ne veut pas garder un enregistrement "declined" en base)
    @friendship.destroy

    redirect_back fallback_location: profil_path,
                  notice: "Demande d'ami refusée."
  end

  # DELETE /users/:user_id/friendship
  # Annule une demande en attente ou retire un ami
  def destroy
    # Cherche la friendship initiée par current_user vers cet utilisateur
    @friendship = current_user.friendships.find_by(friend_id: params[:user_id])

    if @friendship.nil?
      redirect_back fallback_location: user_profil_path(params[:user_id]), alert: "Aucune relation trouvée."
      return
    end

    authorize @friendship

    @friendship.destroy

    if @friendship.accepted?
      redirect_back fallback_location: user_profil_path(params[:user_id]), notice: "Ami retiré de votre liste."
    else
      redirect_back fallback_location: user_profil_path(params[:user_id]), notice: "Demande d'ami annulée."
    end
  end
end
