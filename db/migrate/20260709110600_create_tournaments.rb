# Table des tournois — fondation de la feature Tournoi (Lot 1 : page liste).
# Calquée sur `matches`, mais allégée : pas de chat/vote/paiement ici, on ajoutera
# les métiers de chaque format (ronde suisse, poules…) dans les lots suivants.
class CreateTournaments < ActiveRecord::Migration[8.1]
  def change
    create_table :tournaments do |t|
      # Identité / URL
      t.string  :name, null: false           # nom affiché du tournoi
      t.text    :description                  # description facultative
      t.string  :slug, null: false            # URL propre (concern Sluggable)
      t.string  :banner_image                 # image de couverture manuelle (sinon rotation par sport)

      # Sport & format
      t.references :sport, foreign_key: true  # sport du tournoi (Football, Padel…)
      t.string  :format                       # "ronde_suisse" | "poules" | "championnat"
      t.integer :max_players                  # nombre de joueurs (config figée : 16, 32…)

      # Planning & lieu
      t.date     :date                        # date de l'événement
      t.time     :time                        # heure de début
      t.string   :place                       # lieu libre (texte)
      t.references :venue, foreign_key: true  # lieu référencé (optionnel)
      t.datetime :registration_deadline       # date limite d'inscription

      # État & organisateur
      # status : "open" (inscriptions ouvertes) | "in_progress" (lancé) | "completed"
      t.string   :status, null: false, default: "open"
      # user = créateur / admin du tournoi. nullify : on garde le tournoi si le compte part.
      t.references :user, foreign_key: { on_delete: :nullify }

      t.timestamps
    end

    add_index :tournaments, :slug, unique: true
    add_index :tournaments, :status
  end
end
