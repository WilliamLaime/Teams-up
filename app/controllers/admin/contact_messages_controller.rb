# Controller admin pour visualiser les messages de contact reçus.
# Hérite de Admin::BaseController — seuls les admins peuvent y accéder.
module Admin
  class ContactMessagesController < Admin::BaseController
    # GET /admin/contact_messages
    # Liste tous les messages, les non-lus d'abord, puis par date décroissante
    def index
      # order(lu: :asc) → les non-lus (false=0) apparaissent avant les lus (true=1)
      # order(created_at: :desc) → les plus récents en premier dans chaque groupe
      @contact_messages = ContactMessage.order(lu: :asc, created_at: :desc)
    end

    # PATCH /admin/contact_messages/:id/toggle_lu
    # Bascule l'état lu/non-lu d'un message
    def toggle_lu
      # Trouve le message par son id — lève une erreur 404 si introuvable
      @contact_message = ContactMessage.find(params[:id])

      # ! inverse la valeur booléenne : true → false, false → true
      @contact_message.update(lu: !@contact_message.lu)

      # Redirige vers la liste avec un message flash selon le nouvel état
      if @contact_message.lu?
        redirect_to admin_contact_messages_path, notice: "Message marqué comme lu."
      else
        redirect_to admin_contact_messages_path, notice: "Message marqué comme non lu."
      end
    end

    # POST /admin/contact_messages/:id/reply
    # Envoie un email de réponse à l'expéditeur et marque le message comme lu
    def reply
      @contact_message = ContactMessage.find(params[:id])
      reply_body       = params[:reply_body].to_s.strip

      # Vérifie que la réponse n'est pas vide
      if reply_body.blank?
        redirect_to admin_contact_messages_path,
                    alert: "La réponse ne peut pas être vide."
        return
      end

      # Envoie l'email de réponse via le mailer
      # deliver_now → envoi immédiat (synchrone)
      ContactMessageMailer.reply(@contact_message, reply_body).deliver_now

      # Marque le message comme lu maintenant qu'on y a répondu
      @contact_message.update(lu: true)

      redirect_to admin_contact_messages_path,
                  notice: "Réponse envoyée à #{@contact_message.email}."
    end
  end
end
