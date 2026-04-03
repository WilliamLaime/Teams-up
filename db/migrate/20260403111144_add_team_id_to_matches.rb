class AddTeamIdToMatches < ActiveRecord::Migration[8.1]
  def change
    # team_id est optionnel — seuls les matchs d'équipe l'ont renseigné
    add_reference :matches, :team, null: true, foreign_key: true
  end
end
