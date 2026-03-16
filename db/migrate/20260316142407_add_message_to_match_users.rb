class AddMessageToMatchUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :match_users, :message, :text
  end
end
