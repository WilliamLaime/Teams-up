class AddVisibilityAndTokenToMatches < ActiveRecord::Migration[8.1]
  def change
    # "public" par défaut — les matchs existants restent publics
    add_column :matches, :visibility, :string, default: "public", null: false
    # Token unique pour partager un lien privé
    add_column :matches, :private_token, :string
    add_index  :matches, :private_token, unique: true
  end
end
