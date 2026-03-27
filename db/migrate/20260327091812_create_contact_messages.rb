class CreateContactMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_messages do |t|
      t.string :prenom,  null: false
      t.string :nom,     null: false
      t.string :email,   null: false
      t.string :sujet,   null: false
      t.text   :message, null: false
      # Lu/non-lu — false par défaut (message non lu à l'arrivée)
      t.boolean :lu, default: false, null: false

      t.timestamps
    end
  end
end
