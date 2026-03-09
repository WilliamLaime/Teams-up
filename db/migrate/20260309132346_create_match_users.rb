class CreateMatchUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :match_users do |t|
      t.string :role
      t.references :user, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true

      t.timestamps
    end
  end
end
