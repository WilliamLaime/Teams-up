# Mailer pour répondre aux messages de contact reçus via le formulaire /contact.
# Envoyé depuis l'espace admin par un administrateur.
class ContactMessageMailer < ApplicationMailer
  # Envoie un email de réponse à l'expéditeur du message de contact.
  #
  # @param contact_message [ContactMessage] le message original reçu
  # @param reply_body [String] le texte de la réponse rédigée par l'admin
  def reply(contact_message, reply_body)
    # On stocke les données en variables d'instance pour les utiliser dans la vue
    @contact_message = contact_message
    @reply_body      = reply_body

    mail(
      to:      "#{@contact_message.prenom} #{@contact_message.nom} <#{@contact_message.email}>",
      subject: "Re : #{@contact_message.sujet}"
    )
  end
end
