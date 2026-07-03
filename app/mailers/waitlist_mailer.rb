# Mailer pour l'annonce de lancement aux inscrits en waitlist.
# Envoyé depuis l'espace admin via Admin::WaitlistEntriesController#send_launch_email.
class WaitlistMailer < ApplicationMailer
  # Annonce de lancement — envoyé à chaque email de la waitlist.
  # @param email [String] l'adresse email du destinataire
  def launch_announcement(email)
    # On stocke l'email dans une variable d'instance pour la vue
    @email      = email
    # URL de la page d'inscription — lien principal du CTA
    @signup_url = new_user_registration_url

    mail(
      to: email,
      subject: "Teams-Up est lancé, crée ton compte maintenant !"
    )
  end
end
