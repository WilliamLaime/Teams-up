class CreateUserSports < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :sport, null: false, foreign_key: true

      t.timestamps
    end
  end
end
