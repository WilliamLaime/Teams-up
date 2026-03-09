class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :message
      t.string :link
      t.boolean :read, default: false, null: false

      t.timestamps
    end
  end
end
