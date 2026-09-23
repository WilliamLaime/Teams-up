# ── Mail récapitulatif d'une conversation, à la fin de la fenêtre de 3 min ───
# Programmé par ChatMessageNotifier au 1er message d'une fenêtre. Au moment de
# s'exécuter, il envoie UN mail avec tous les messages que le destinataire n'a
# toujours pas lus — ou rien du tout s'il les a lus dans l'app entre-temps.
#
# Sécurité retry : l'argument est un id scalaire (pas de GlobalID), le job ne
# lève donc pas de DeserializationError si la conversation a été supprimée.
class ChatEmailDigestJob < ApplicationJob
  queue_as :default

  # Erreurs réseau du fournisseur mail : on réessaie. La fenêtre reste ouverte
  # pendant les tentatives (pending_since non nul), les nouveaux messages
  # n'empilent donc pas de jobs supplémentaires.
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET,
           wait: :polynomially_longer, attempts: 5

  def perform(digest_id)
    digest = ChatEmailDigest.find_by(id: digest_id)
    return if digest.nil?

    # Conversation supprimée entre-temps (match annulé, tour régénéré…) : la
    # ligne n'a plus de raison d'être.
    return digest.destroy if digest.chattable.nil?

    # Instant figé : tout ce qui arrive après sera traité par la fenêtre suivante.
    cutoff = Time.current
    messages = digest.accessible? ? digest.unread_messages(up_to: cutoff).includes(user: :profil).to_a : []

    if messages.empty?
      # Tout a été lu dans l'app : la notification de la cloche n'a plus d'objet.
      mark_bell_notification_read(digest)
    elsif email_enabled?(digest.user)
      ChatMailer.new_messages(digest, messages).deliver_now
    end

    close_window(digest, cutoff)
  end

  private

  def email_enabled?(user)
    user.profil&.chat_email_notifications?
  end

  # Ferme la fenêtre. Un message arrivé PENDANT ce job (après `cutoff`) n'a pas
  # pu ouvrir de fenêtre puisqu'elle était encore ouverte : on la rouvre pour
  # lui, sinon il ne serait jamais notifié.
  def close_window(digest, cutoff)
    digest.update!(pending_since: nil, last_sent_at: cutoff)

    late = digest.accessible? && digest.chattable.messages
                                       .where.not(user_id: digest.user_id)
                                       .where("messages.created_at > ?", cutoff)
                                       .exists?
    return unless late

    reopened = ChatEmailDigest.where(id: digest.id, pending_since: nil)
                              .update_all(pending_since: Time.current) == 1
    self.class.set(wait: ChatEmailDigest::WINDOW).perform_later(digest.id) if reopened
  end

  def mark_bell_notification_read(digest)
    Notification.where(user_id: digest.user_id, notif_type: ChatMessageNotifier::NOTIF_TYPE,
                       link: digest.chat_path, read: false)
                .find_each { |notification| notification.update!(read: true) }
  end
end
