class ReplaceTeamInvitationsUniqueIndexWithPartial < ActiveRecord::Migration[8.1]
  def change
    # Supprime l'index unique global (bloquait les ré-invitations après refus/acceptation)
    remove_index :team_invitations, [:team_id, :invitee_id]

    # Ajoute un index unique partiel : une seule invitation pending par (team, invitee)
    add_index :team_invitations, [:team_id, :invitee_id],
              unique: true,
              where: "status = 'pending'",
              name: "index_team_invitations_pending_unique"
  end
end
