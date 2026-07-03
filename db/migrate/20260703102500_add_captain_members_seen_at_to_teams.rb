class AddCaptainMembersSeenAtToTeams < ActiveRecord::Migration[8.1]
  # Horodatage de la dernière fois où le capitaine a "vu" l'arrivée des membres
  # de son équipe. Sert à afficher un point de notification (navbar + carte équipe)
  # quand un nouveau membre a rejoint depuis cette date.
  # Nullable : pour les équipes existantes, on retombe sur teams.created_at
  # (aucun faux point pour les membres historiques).
  def change
    add_column :teams, :captain_members_seen_at, :datetime
  end
end
