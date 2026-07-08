class AddEndTimeToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :end_time, :time
  end
end
