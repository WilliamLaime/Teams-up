class AddVenueToMatches < ActiveRecord::Migration[8.1]
  def change
    # null: true → le lieu est optionnel (les matchs existants n'ont pas encore de venue)
    add_reference :matches, :venue, null: true, foreign_key: true
  end
end
