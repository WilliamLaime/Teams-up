class AddLastReadAtToMatchUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :match_users, :last_read_at, :datetime
  end
end
