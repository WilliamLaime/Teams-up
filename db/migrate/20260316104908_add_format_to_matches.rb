class AddFormatToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :format, :string
  end
end
