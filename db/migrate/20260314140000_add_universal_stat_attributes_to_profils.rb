class AddUniversalStatAttributesToProfils < ActiveRecord::Migration[8.0]
  def change
    # 4 nouveaux attributs universels — valables pour tous les sports
    # Valeur par défaut 0, ne peut pas être NULL
    add_column :profils, :attr_endurance, :integer, default: 0, null: false
    add_column :profils, :attr_tactics,   :integer, default: 0, null: false
    add_column :profils, :attr_teamwork,  :integer, default: 0, null: false
    add_column :profils, :attr_mental,    :integer, default: 0, null: false
  end
end
