class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    # false par défaut — aucun user ne peut devenir admin via l'app
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
