class AddPricePerPlayerToMatches < ActiveRecord::Migration[8.1]
  def change
    # Ajoute le prix par joueur (en centimes d'euro), défaut 0 = gratuit
    add_column :matches, :price_per_player, :integer, default: 0
  end
end
