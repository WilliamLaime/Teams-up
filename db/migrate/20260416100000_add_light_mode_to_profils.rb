# Migration : ajout de la colonne light_mode sur la table profils
# Cette colonne permet de stocker la préférence de thème de l'utilisateur.
# false (par défaut) = thème sombre (comportement actuel de l'app)
# true = thème clair

class AddLightModeToProfils < ActiveRecord::Migration[8.1]
  def up
    # Ajoute la colonne booléenne light_mode avec false comme valeur par défaut
    # null: false garantit qu'on a toujours une valeur définie
    add_column :profils, :light_mode, :boolean, default: false, null: false
  end

  def down
    # Supprime la colonne si on veut annuler la migration
    remove_column :profils, :light_mode
  end
end
