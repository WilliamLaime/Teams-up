class Message < ApplicationRecord
  # Un message appartient à un utilisateur (l'expéditeur)
  belongs_to :user

  # Un message appartient à un match (la conversation de groupe)
  belongs_to :match

  # Validation : le contenu est obligatoire et limité à 1000 caractères
  validates :content, presence: true, length: { maximum: 1000 }

  # Après la création d'un message, on le diffuse en temps réel
  # via Turbo Streams sur le stream spécifique au match
  # Cela met à jour la liste des messages sur toutes les pages ouvertes
  after_create_commit :broadcast_message, :reactivate_dismissed_conversations, :broadcast_unread_notifications

  private

  def broadcast_unread_notifications
    # Pour chaque participant du match SAUF l'expéditeur :
    # met à jour l'item de sidebar avec le badge non-lu (petit rond vert)
    # via le stream personnel "user_conversations_<id>" de chaque participant
    match.match_users.where.not(user_id: user_id).each do |mu|
      Turbo::StreamsChannel.broadcast_replace_to(
        "user_conversations_#{mu.user_id}",   # stream personnel du destinataire
        target: "sticky-convo-#{match_id}",   # l'item à remplacer dans sa sidebar
        partial: "shared/sticky_convo_item",
        locals: { match: match, match_user: mu }
      )
    end
  end

  def reactivate_dismissed_conversations
    # Si des participants avaient dismissé cette conversation (bouton poubelle),
    # on réinitialise leur chat_dismissed_at → la conversation réapparaîtra
    # au prochain chargement de page pour ces utilisateurs
    match.match_users.where.not(chat_dismissed_at: nil).update_all(chat_dismissed_at: nil)
  end

  def broadcast_message
    # Diffuse le nouveau message en l'ajoutant à la fin de la liste (#chat-messages)
    # Tous les abonnés au stream "match_chat_<id>" le reçoivent instantanément

    # 1. Cible la modal du chat sur la page show du match
    broadcast_append_to(
      "match_chat_#{match_id}",      # nom du stream (unique par match)
      target: "chat-messages",       # id de la zone de messages dans la modal
      partial: "messages/message",   # la vue partielle à rendre
      locals: { message: self }      # on passe le message à la partielle
    )

    # 2. Met à jour la preview card (les 2 derniers messages affichés sous le header).
    # On utilise broadcast_update_to pour remplacer le CONTENU du div#chat-preview-list-X
    # sans perdre son id (contrairement à broadcast_replace_to qui supprimerait l'élément).
    # Même stream que la modal → un seul abonnement turbo_stream_from suffit pour les deux.
    broadcast_update_to(
      "match_chat_#{match_id}",
      target: "chat-preview-list-#{match_id}",  # id du conteneur de preview dans show.html.erb
      partial: "matches/chat_preview_list",
      locals: { match: match }
    )

    # 3. Cible le panneau sticky chat (visible sur toutes les pages)
    # On utilise un stream DIFFÉRENT ("match_chat_sticky_<id>") pour éviter que
    # les utilisateurs sur la page show du match reçoivent le message en double
    # (car ils seraient abonnés aux deux streams en même temps)
    broadcast_append_to(
      "match_chat_sticky_#{match_id}",  # stream distinct du modal
      target: "sticky-chat-messages",   # id de la zone de messages dans le sticky chat
      partial: "messages/message",
      locals: { message: self }
    )
  end
end
