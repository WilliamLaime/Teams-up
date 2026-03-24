class CreateFriendships < ActiveRecord::Migration[8.1]
  def change
    create_table :friendships do |t|
      # L'utilisateur qui a ajouté l'ami
      t.references :user,   null: false, foreign_key: true
      # L'utilisateur qui a été ajouté comme ami
      t.references :friend, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Empêche les doublons : un même couple user/friend ne peut exister qu'une fois
    add_index :friendships, [:user_id, :friend_id], unique: true
  end
end
