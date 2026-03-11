class MatchChatChannel < ApplicationCable::Channel
  # L'utilisateur s'abonne en passant l'ID du match
  # Ex : consumer.subscriptions.create({ channel: "MatchChatChannel", match_id: 7 })
  def subscribed
    # find_by DOIT recevoir un hash { id: ... } — sans ça, il renvoie nil
    @match = Match.find_by(id: params[:match_id])

    # Vérifie que le match existe et que l'utilisateur est participant approuvé
    if @match && participant?
      # S'abonne au stream de frappe spécifique au match
      stream_from "match_chat_typing_#{@match.id}"
    else
      reject # refuse la connexion si non autorisé
    end
  end

  def unsubscribed
    # Rien à faire — ActionCable gère le nettoyage automatiquement
  end

  # Appelé quand l'utilisateur envoie un signal "typing" depuis le JS
  # Diffuse le nom de l'expéditeur à tous les autres abonnés
  def typing(_data)
    # Guard : si @match ou current_user est nil, on ne fait rien
    return unless @match && current_user

    ActionCable.server.broadcast(
      "match_chat_typing_#{@match.id}",
      {
        user_name: current_user.display_name,
        user_id: current_user.id
      }
    )
  end

  private

  # Vérifie que l'utilisateur est bien un participant approuvé ou l'organisateur
  def participant?
    match_user = @match.match_users.find_by(user: current_user)
    match_user && (match_user.approved? || match_user.role == "organisateur")
  end
end
