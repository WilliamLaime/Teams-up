class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      # Infos de base
      t.string :name, null: false
      t.text :description

      # Blason : image uploadée via Active Storage (pas de colonne ici, géré par has_one_attached)
      # SVG généré côté client et stocké en base (alternative légère à l'upload)
      t.text :badge_svg

      # Le captain est l'user qui a créé l'équipe (et peut la supprimer)
      t.references :captain, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Unicité du nom d'équipe par captain (un user ne peut pas avoir deux équipes du même nom)
    add_index :teams, [:name, :captain_id], unique: true
  end
end
