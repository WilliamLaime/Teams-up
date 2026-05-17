# Migration : crée la table waitlist_entries pour stocker les emails des
# visiteurs intéressés par le lancement de Teams-up.
class CreateWaitlistEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :waitlist_entries do |t|
      # Email du visiteur — not null car c'est le seul champ utile
      t.string :email, null: false
      t.timestamps
    end

    # Index unique insensible à la casse côté base (unicité gérée aussi dans le modèle)
    add_index :waitlist_entries, :email, unique: true
  end
end
