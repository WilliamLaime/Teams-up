class AddSlackPrepSentAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :slack_prep_sent_at, :datetime
  end
end
