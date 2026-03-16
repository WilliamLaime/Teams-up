class CreateSports < ActiveRecord::Migration[8.1]
  def change
    create_table :sports do |t|
      t.string :name
      t.string :icon
      t.string :slug

      t.timestamps
    end
  end
end
