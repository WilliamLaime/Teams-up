class AddBookingLinkToMatchesAndPaymentConfirmedToMatchUsers < ActiveRecord::Migration[8.1]
  def change
    # Lien de réservation du terrain — facultatif, renseigné par l'organisateur
    add_column :matches, :booking_link, :string

    # Suivi du paiement par joueur — false par défaut (non payé)
    add_column :match_users, :payment_confirmed, :boolean, default: false, null: false
  end
end
