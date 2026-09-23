# ChatMailer — mail récapitulatif des messages de chat reçus
# Envoyé par ChatEmailDigestJob à la fin d'une fenêtre de 3 min (cf.
# ChatMessageNotifier) : un seul mail regroupe les messages non lus d'une même
# conversation, quel que soit son type (privé, match, équipe, match de tournoi).
class ChatMailer < ApplicationMailer
  # @param digest   [ChatEmailDigest] destinataire + conversation
  # @param messages [Array<Message>]  messages non lus, du plus ancien au plus récent
  def new_messages(digest, messages)
    @recipient = digest.user
    @digest    = digest
    @messages  = messages.last(ChatEmailDigest::MAX_MESSAGES_IN_EMAIL)
    @hidden_count = messages.size - @messages.size
    @senders   = messages.map(&:user).uniq
    # root_url du mailer (config.action_mailer.default_url_options) : même hôte
    # que tous les autres liens des mails.
    @chat_url  = root_url.chomp("/") + digest.chat_path
    @unsubscribe_url = chat_email_unsubscribe_url(
      token: @recipient.profil.signed_id(purpose: ChatEmailUnsubscribesController::TOKEN_PURPOSE)
    )

    # Désinscription en un clic depuis le client mail (Gmail, Apple Mail…) —
    # RFC 8058 : le client envoie un POST sur l'URL, sans passer par la page.
    headers["List-Unsubscribe"]      = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    mail(to: @recipient.email, subject: subject_for(messages))
  end

  private

  # « 💬 Nouveau message de Paul » en privé, sinon le nom du groupe :
  # « 💬 3 nouveaux messages · Foot du jeudi ».
  def subject_for(messages)
    label = messages.size > 1 ? "#{messages.size} nouveaux messages" : "Nouveau message"
    context = @digest.private_chat? ? "de #{messages.first.user.display_name}" : "· #{@digest.chat_title}"
    "💬 #{label} #{context}"
  end
end
