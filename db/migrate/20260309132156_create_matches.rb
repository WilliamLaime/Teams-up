class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.string :title
      t.string :description
      t.date :date
      t.time :time
      t.string :place
      t.integer :player_left
      t.string :level

      t.timestamps
    end
  end
end
