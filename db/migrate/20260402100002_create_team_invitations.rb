class CreateTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :team_invitations do |t|
      t.references :team,    null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users } # le captain qui invite
      t.references :invitee, null: false, foreign_key: { to_table: :users } # le user invité

      # Statut de l'invitation : "pending" | "accepted" | "refused"
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    # Un user ne peut avoir qu'une invitation en attente par équipe
    add_index :team_invitations, [:team_id, :invitee_id], unique: true
  end
end
