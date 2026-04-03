class CreateTeamMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :team_members do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Rôle dans l'équipe : "captain" ou "member"
      t.string :role, null: false, default: "member"

      # Date d'entrée dans l'équipe (renseignée à l'acceptation de l'invitation)
      t.datetime :joined_at

      t.timestamps
    end

    # Un user ne peut être membre qu'une seule fois par équipe
    add_index :team_members, [:team_id, :user_id], unique: true
  end
end
