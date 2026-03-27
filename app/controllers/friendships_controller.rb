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
      redirect_back fallback_location: user_profil_path(@friend),
                    alert: "Vous êtes déjà amis avec #{@friend.display_name}."
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
      # Nettoie les anciennes notifications "friend_request" de cet actor vers ce destinataire
      # au cas où elles n'auraient pas été supprimées lors d'un refus ou retrait précédent
      Notification.where(user: @friend, actor_id: current_user.id, notif_type: "friend_request").destroy_all

      # Met à jour le bouton ami en temps réel pour les deux côtés
      broadcast_friend_button_update(current_user, @friend) # A voit profil B : passe à "En attente"
      broadcast_friend_button_update(@friend, current_user) # B voit profil A : passe à "Accepter/Refuser"

      # Envoie une notification au destinataire avec le type "friend_request"
      # et l'actor_id = current_user → pour afficher les boutons Accepter/Refuser
      # directement dans la notification sans aller sur le profil
      Notification.create(
        user:       @friend,
        message:    "👋 #{current_user.display_name} vous a envoyé une demande d'ami.",
        link:       user_profil_path(current_user),
        notif_type: "friend_request",
        actor_id:   current_user.id
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

    # Met à jour la notification "friend_request" : on la passe en lue avec un message de confirmation
    # Les boutons Accepter/Refuser disparaissent automatiquement car pending_request_from? renvoie false
    Notification.where(user: current_user, actor_id: @sender.id, notif_type: "friend_request")
                .update_all(read: true, message: "✅ Vous avez accepté la demande d'ami de #{@sender.display_name}.")

    # Met à jour le bouton ami en temps réel pour les deux côtés
    broadcast_friend_button_update(current_user, @sender) # B voit profil A : passe à "Amis"
    broadcast_friend_button_update(@sender, current_user) # A voit profil B : passe à "Amis"

    # Met à jour la liste d'amis en temps réel sur le propre profil de chaque user
    broadcast_friends_list_update(current_user) # la liste de B ajoute A en direct
    broadcast_friends_list_update(@sender)       # la liste de A ajoute B en direct

    # Notifie l'expéditeur que sa demande a été acceptée
    Notification.create(
      user: @sender,
      message: "🎉 #{current_user.display_name} a accepté votre demande d'ami !",
      link: user_profil_path(current_user)
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

    # Met à jour la notification "friend_request" : on la passe en lue avec un message de confirmation
    # Les boutons Accepter/Refuser disparaissent automatiquement car pending_request_from? renvoie false
    Notification.where(user: current_user, actor_id: @sender.id, notif_type: "friend_request")
                .update_all(read: true, message: "❌ Vous avez refusé la demande d'ami de #{@sender.display_name}.")

    # Met à jour le bouton ami en temps réel pour les deux côtés
    broadcast_friend_button_update(current_user, @sender) # B voit profil A : passe à "Ajouter"
    broadcast_friend_button_update(@sender, current_user) # A voit profil B : passe à "Ajouter"

    redirect_back fallback_location: profil_path,
                  notice: "Demande d'ami refusée."
  end

  # DELETE /users/:user_id/friendship
  # Annule une demande en attente ou retire un ami
  def destroy
    # Cherche d'abord la friendship initiée par current_user vers cet utilisateur
    @friendship = current_user.friendships.find_by(friend_id: params[:user_id])

    # Si pas trouvée, cherche dans les amitiés reçues (l'autre a initié)
    # uniquement si elles sont acceptées (on ne peut pas "annuler" à la place de l'autre)
    if @friendship.nil?
      @friendship = current_user.inverse_friendships.accepted.find_by(user_id: params[:user_id])
    end

    if @friendship.nil?
      redirect_back fallback_location: user_profil_path(params[:user_id]), alert: "Aucune relation trouvée."
      return
    end

    authorize @friendship

    # Mémorise l'état et les ids avant suppression
    was_accepted = @friendship.accepted?
    other_user_id = (@friendship.user_id == current_user.id) ? @friendship.friend_id : @friendship.user_id
    @friendship.destroy

    # Supprime toutes les notifications "friend_request" liées à cette relation dans les deux sens
    # pour éviter qu'elles réapparaissent si une nouvelle demande est envoyée plus tard
    Notification.where(user: current_user, actor_id: other_user_id, notif_type: "friend_request").destroy_all
    Notification.where(user_id: other_user_id, actor_id: current_user.id, notif_type: "friend_request").destroy_all

    # Met à jour le bouton ami en temps réel pour les deux côtés
    other_user = User.find(other_user_id)
    broadcast_friend_button_update(current_user, other_user) # passe à "Ajouter"
    broadcast_friend_button_update(other_user, current_user) # passe à "Ajouter"

    # Met à jour la liste d'amis en temps réel sur le propre profil de chaque user
    broadcast_friends_list_update(current_user) # la liste de current_user retire other_user
    broadcast_friends_list_update(other_user)   # la liste de other_user retire current_user

    if was_accepted
      redirect_back fallback_location: user_profil_path(params[:user_id]), notice: "Ami retiré de votre liste."
    else
      redirect_back fallback_location: user_profil_path(params[:user_id]), notice: "Demande d'ami annulée."
    end
  end

  private

  # Broadcast la liste d'amis mise à jour vers le profil de l'utilisateur (via ActionCable)
  # Uniquement utile si l'utilisateur est sur son propre profil (seul abonné à ce stream)
  # user : le propriétaire du profil dont la liste d'amis doit se mettre à jour
  def broadcast_friends_list_update(user)
    Turbo::StreamsChannel.broadcast_update_to(
      "friends_list_#{user.id}",              # canal auquel seul le propriétaire est abonné
      target:  "friends_list_#{user.id}",     # id du turbo_frame dans le DOM
      partial: "profils/friends_list",
      locals:  {
        friends:          user.all_friends.includes(:profil),
        pending_requests: user.inverse_friendships.pending.includes(user: :profil),
        own_profile:      true                # on broadcast uniquement pour son propre profil
      }
    )
  end

  # Broadcast le partial _friend_button mis à jour vers le viewer (via ActionCable)
  # Appelé après chaque changement de relation pour mettre à jour le bouton en temps réel
  # viewer      : l'utilisateur qui regarde la page profil
  # profil_user : l'utilisateur dont on consulte le profil
  def broadcast_friend_button_update(viewer, profil_user)
    Turbo::StreamsChannel.broadcast_replace_to(
      "friend_button_#{viewer.id}_#{profil_user.id}",  # canal unique par paire viewer/profil
      target:  "friend_button_#{profil_user.id}",       # id du turbo_frame dans le DOM
      partial: "shared/friend_button",
      locals:  {
        current_user:               viewer,               # passé comme local (pas de session en broadcast)
        profil_user:                profil_user,
        already_friends:            viewer.friends_with?(profil_user),
        pending_sent:               viewer.pending_request_sent_to?(profil_user),
        pending_received:           viewer.pending_friendship_from(profil_user).present?,
        friendship_initiated_by_me: viewer.friendships.accepted.exists?(friend: profil_user)
      }
    )
  end
end
