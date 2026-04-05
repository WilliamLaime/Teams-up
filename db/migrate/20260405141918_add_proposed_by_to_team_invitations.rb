class AddProposedByToTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    # null: true car la colonne n'existe pas sur les invitations déjà créées
    add_reference :team_invitations, :proposed_by, null: true, foreign_key: { to_table: :users }
  end
end
