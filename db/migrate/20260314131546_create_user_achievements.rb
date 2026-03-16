class CreateUserAchievements < ActiveRecord::Migration[8.1]
  def change
    create_table :user_achievements do |t|
      # Référence vers l'utilisateur qui a débloqué l'achievement
      t.references :user, null: false, foreign_key: true
      # Référence vers l'achievement débloqué
      t.references :achievement, null: false, foreign_key: true

      t.timestamps
    end

    # Index unique : un utilisateur ne peut débloquer le même achievement qu'une fois
    add_index :user_achievements, [:user_id, :achievement_id], unique: true
  end
end
