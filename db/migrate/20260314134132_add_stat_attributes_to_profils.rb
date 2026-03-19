class AddStatAttributesToProfils < ActiveRecord::Migration[8.1]
  def change
    # Les 4 attributs RPG — commencent tous à 0
    add_column :profils, :attr_attack,    :integer, default: 0, null: false
    add_column :profils, :attr_defense,   :integer, default: 0, null: false
    add_column :profils, :attr_speed,     :integer, default: 0, null: false
    add_column :profils, :attr_precision, :integer, default: 0, null: false
    # Points en attente de distribution — gagnés à chaque montée de niveau
    add_column :profils, :stat_points,    :integer, default: 0, null: false
  end
end
