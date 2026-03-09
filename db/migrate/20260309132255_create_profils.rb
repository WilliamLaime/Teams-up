class CreateProfils < ActiveRecord::Migration[8.1]
  def change
    create_table :profils do |t|
      t.string :name
      t.string :description
      t.string :level
      t.decimal :localisation
      t.datetime :time_available
      t.string :role
      t.string :phone
      t.string :address
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
