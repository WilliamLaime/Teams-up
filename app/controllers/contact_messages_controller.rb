# Controller pour la création d'un message de contact.
# Gère uniquement le POST — le GET est géré par PagesController#contact.
# Le formulaire est public (pas besoin d'être connecté).
class ContactMessagesController < ApplicationController
  # Le formulaire de contact est accessible sans connexion
  skip_before_action :authenticate_user!

  # Désactive Pundit pour ce controller (formulaire public, pas de policy)
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # POST /contact
  # Crée un nouveau message et redirige avec un flash de confirmation
  def create
    # Construit un nouveau message avec les paramètres autorisés
    @contact_message = ContactMessage.new(contact_message_params)

    if @contact_message.save
      # Succès : redirige vers la page de contact avec un message de confirmation
      redirect_to contact_path, notice: "Ton message a bien été envoyé. On te répondra sous 48h !"
    else
      # Échec : réaffiche le formulaire avec les erreurs de validation
      # @contact_message contient les erreurs — form_with les affichera automatiquement
      render "pages/contact", status: :unprocessable_entity
    end
  end

  private

  # Paramètres autorisés — on accepte uniquement les champs attendus du formulaire
  def contact_message_params
    params.require(:contact_message).permit(:prenom, :nom, :email, :sujet, :message)
  end
end
