class AddNullifyToMatchesUserFks < ActiveRecord::Migration[8.1]
  def change
    # Modifie les FK matches.user_id (créateur) et matches.homme_du_match_id
    # pour utiliser on_delete: :nullify (RGPD art. 17)
    # Permet aux matchs de rester en BDD après suppression du créateur/homme du match

    # FK matches.user_id → nullify
    remove_foreign_key :matches, :users
    add_foreign_key :matches, :users, on_delete: :nullify

    # FK matches.homme_du_match_id → nullify (créée via add_reference en migration antérieure)
    remove_foreign_key :matches, column: :homme_du_match_id
    add_foreign_key :matches, :users, column: :homme_du_match_id, on_delete: :nullify
  end
end
