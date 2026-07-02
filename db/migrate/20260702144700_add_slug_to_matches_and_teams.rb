class AddSlugToMatchesAndTeams < ActiveRecord::Migration[8.1]
  # URLs propres (slug) pour les matchs et les équipes, à la place des ids numériques.
  # Étapes : colonne nullable → backfill des enregistrements existants → index unique
  # → contrainte NOT NULL.
  def up
    add_column :matches, :slug, :string
    add_column :teams, :slug, :string

    backfill_slugs(Match, :title)
    backfill_slugs(Team, :name)

    add_index :matches, :slug, unique: true
    add_index :teams, :slug, unique: true

    change_column_null :matches, :slug, false
    change_column_null :teams, :slug, false
  end

  def down
    remove_column :matches, :slug
    remove_column :teams, :slug
  end

  private

  # Génère un slug "<base>-<suffixe>" pour chaque enregistrement existant.
  # On réplique la logique de Sluggable ici (les callbacks ne s'exécutent pas
  # sur les enregistrements déjà en base) en restant robuste aux collisions.
  def backfill_slugs(klass, source_column)
    used = []
    klass.reset_column_information
    klass.where(slug: nil).find_each do |record|
      base = record.public_send(source_column).to_s.parameterize.first(60)
      base = klass.name.downcase if base.blank?
      loop do
        candidate = "#{base}-#{SecureRandom.alphanumeric(6).downcase}"
        unless used.include?(candidate) || klass.exists?(slug: candidate)
          used << candidate
          record.update_column(:slug, candidate)
          break
        end
      end
    end
  end
end
