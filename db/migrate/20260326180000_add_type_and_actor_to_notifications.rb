class AddTypeAndActorToNotifications < ActiveRecord::Migration[7.1]
  def change
    # notif_type : catégorie de la notification (ex: "friend_request")
    # Permet d'afficher des boutons d'action directement dans la notification
    add_column :notifications, :notif_type, :string

    # actor_id : l'utilisateur à l'origine de la notification
    # Ex: pour une demande d'ami, c'est celui qui a envoyé la demande
    add_column :notifications, :actor_id, :integer
  end
end
