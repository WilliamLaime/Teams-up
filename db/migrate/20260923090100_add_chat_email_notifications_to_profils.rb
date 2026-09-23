class AddChatEmailNotificationsToProfils < ActiveRecord::Migration[8.1]
  # Préférence « recevoir un mail quand on m'écrit » — activée par défaut.
  # Décochable depuis le formulaire du profil ou via le lien de désinscription
  # présent dans chaque mail. Elle ne coupe QUE le mail : la notification dans la
  # cloche du header reste envoyée.
  def change
    add_column :profils, :chat_email_notifications, :boolean, default: true, null: false
  end
end
