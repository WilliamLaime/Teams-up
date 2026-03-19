class CreateAchievements < ActiveRecord::Migration[8.1]
  def change
    create_table :achievements do |t|
      # Identifiant unique de l'achievement (ex: "first_join")
      t.string :key, null: false
      # Nom affiché à l'utilisateur
      t.string :name, null: false
      # Description de comment débloquer cet achievement
      t.string :description
      # Points XP gagnés lors du déblocage
      t.integer :xp_reward, default: 0, null: false
      # Emoji affiché comme icône
      t.string :icon_emoji
      # Catégorie : "match", "social", "profile"
      t.string :category, default: "match"

      t.timestamps
    end

    # Index unique sur key pour éviter les doublons d'achievements
    add_index :achievements, :key, unique: true
  end
end
