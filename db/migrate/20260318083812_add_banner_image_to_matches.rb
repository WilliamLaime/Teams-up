class AddBannerImageToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :banner_image, :string
  end
end
