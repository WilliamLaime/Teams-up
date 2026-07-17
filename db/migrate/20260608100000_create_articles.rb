class CreateArticles < ActiveRecord::Migration[8.0]
  # Crée la table articles pour le blog SEO.
  # Chaque article a un slug unique utilisé dans l'URL (/blog/mon-article).
  # published_at NULL = brouillon, sinon = publié à cette date.
  def change
    create_table :articles do |t|
      t.string   :title,            null: false               # Titre de l'article (h1 + <title>)
      t.string   :slug,             null: false               # URL-friendly : "comment-trouver-un-match"
      t.text     :body,             null: false               # Corps de l'article (texte riche)
      t.string   :meta_description                            # Description SEO (160 caractères max)
      t.string   :category                                    # Catégorie : "conseils", "sport", "équipe"
      t.string   :cover_image_url                             # URL de l'image de couverture (og:image)
      t.datetime :published_at                                # NULL = brouillon, sinon = date de publication
      t.integer  :reading_time_minutes, default: 1            # Temps de lecture estimé en minutes

      t.timestamps
    end

    # Index sur le slug pour les lookups /blog/:slug (fréquents)
    add_index :articles, :slug,         unique: true
    # Index sur published_at pour trier et filtrer les articles publiés
    add_index :articles, :published_at
    # Index sur la catégorie pour filtrer par catégorie
    add_index :articles, :category
  end
end
