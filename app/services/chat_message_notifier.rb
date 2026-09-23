# ── Notifie les destinataires d'un nouveau message de chat ───────────────────
# Appelé après la création de chaque Message (Message#notify_recipients), pour
# les 4 types de chat : privé, match, équipe, match de tournoi.
#
# Deux canaux, un même rythme :
#   1. une notification dans la cloche du header — IMMÉDIATE ;
#   2. un mail récapitulatif — 3 min plus tard (ChatEmailDigestJob), avec tous
#      les messages encore non lus de la fenêtre.
#
# Anti-spam : le 1er message « ouvre une fenêtre » de 3 min pour chaque
# destinataire. Les messages suivants arrivés pendant la fenêtre ne déclenchent
# rien de plus — ils seront simplement repris dans le mail. Résultat : 3 lignes
# envoyées d'affilée = 1 notification + 1 mail.
#
# Usage : ChatMessageNotifier.call(message)
class ChatMessageNotifier
  NOTIF_TYPE = "chat_message".freeze

  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message   = message
    @sender    = message.user
    @chattable = ChatEmailDigest.chattable_for(message)
  end

  def call
    return if @chattable.nil?

    recipient_ids = ChatEmailDigest.participant_ids_for(@chattable) - [@sender.id]
    recipient_ids.each { |recipient_id| notify(recipient_id) }
  end

  private

  def notify(recipient_id)
    digest = find_or_create_digest(recipient_id)
    # Fenêtre déjà ouverte : un mail est déjà programmé, il reprendra ce message.
    return unless claim_window?(digest)

    create_bell_notification(digest)
    ChatEmailDigestJob.set(wait: ChatEmailDigest::WINDOW).perform_later(digest.id)
  end

  # insert … ON CONFLICT DO NOTHING : deux messages simultanés ne peuvent pas
  # créer deux lignes pour le même (destinataire, conversation) — l'index unique
  # tranche, et la ligne existante est conservée telle quelle.
  def find_or_create_digest(recipient_id)
    attributes = { user_id: recipient_id, chattable_type: @chattable.class.name, chattable_id: @chattable.id }
    now = Time.current
    ChatEmailDigest.insert(
      attributes.merge(created_at: now, updated_at: now),
      unique_by: :index_chat_email_digests_on_user_and_chattable
    )
    ChatEmailDigest.find_by!(attributes)
  end

  # ── Ouverture atomique de la fenêtre ──────────────────────────────────────
  # Un seul UPDATE conditionnel : PostgreSQL garantit qu'une seule requête
  # concurrente passe pending_since de NULL à maintenant. Celle qui renvoie 1
  # programme le mail, les autres (0 ligne modifiée) n'ont rien à faire.
  #
  # Une fenêtre restée ouverte bien au-delà des 3 min (job perdu : worker
  # redémarré, adapter :async en dev…) est considérée comme close, sinon la
  # conversation ne serait plus jamais notifiée.
  def claim_window?(digest)
    now = Time.current
    ChatEmailDigest.where(id: digest.id)
                   .where("pending_since IS NULL OR pending_since < ?", now - ChatEmailDigest::STALE_AFTER)
                   .update_all(pending_since: now, updated_at: now) == 1
  end

  # ── Notification dans la cloche ───────────────────────────────────────────
  # Une seule notification non lue par conversation : l'ancienne est remplacée,
  # ce qui la fait remonter en tête et déclenche le rafraîchissement temps réel
  # de la cloche (Notification#broadcast_notification_bell, sur create).
  # Créée même si le destinataire a désactivé les mails : l'option ne coupe
  # que le mail.
  def create_bell_notification(digest)
    link = digest.chat_path

    Notification.where(user_id: digest.user_id, notif_type: NOTIF_TYPE, link: link, read: false).destroy_all
    Notification.create!(
      user_id: digest.user_id,
      actor: @sender,
      notif_type: NOTIF_TYPE,
      link: link,
      message: notification_text(digest)
    )
  end

  def notification_text(digest)
    if digest.private_chat?
      "#{@sender.display_name} t'a envoyé un message"
    else
      "Nouveau message de #{@sender.display_name} · #{digest.chat_title}"
    end
  end
end
