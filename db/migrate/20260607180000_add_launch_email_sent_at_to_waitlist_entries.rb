class AddLaunchEmailSentAtToWaitlistEntries < ActiveRecord::Migration[8.0]
  # Ajoute une colonne horodatage pour tracer l'envoi de l'email de lancement.
  # NULL = pas encore envoyé. Remplie automatiquement après envoi réussi.
  # Permet de renvoyer uniquement aux personnes qui n'ont pas encore reçu le mail.
  def change
    add_column :waitlist_entries, :launch_email_sent_at, :datetime
  end
end
