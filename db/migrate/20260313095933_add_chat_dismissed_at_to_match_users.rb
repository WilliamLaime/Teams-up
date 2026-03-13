class AddChatDismissedAtToMatchUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :match_users, :chat_dismissed_at, :datetime
  end
end
