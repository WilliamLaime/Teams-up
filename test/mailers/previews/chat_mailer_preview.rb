# Preview accessible en développement à l'URL :
# http://localhost:3000/rails/mailers/chat_mailer/new_messages
#
# Utilise le dernier message de la base de dev (quel que soit le type de chat) :
# il en faut au moins un, avec un autre participant pour le recevoir.
class ChatMailerPreview < ActionMailer::Preview
  def new_messages
    last_message = Message.order(created_at: :desc).first
    raise "Aucun message en base de dev : envoie un message dans un chat" if last_message.nil?

    chattable = ChatEmailDigest.chattable_for(last_message)
    recipient_id = (ChatEmailDigest.participant_ids_for(chattable) - [last_message.user_id]).first
    raise "Ce chat n'a pas d'autre participant pour recevoir le mail" if recipient_id.nil?

    # new : pas de ligne créée en base juste pour afficher un aperçu
    digest = ChatEmailDigest.new(user: User.find(recipient_id), chattable: chattable)
    messages = chattable.messages.where(user: last_message.user).order(:created_at).last(3)

    ChatMailer.new_messages(digest, messages)
  end
end
