require "csv"

# ─────────────────────────────────────────────────────────────────────────────
# Rake task : importer les établissements sportifs depuis le CSV national
#
# Usage :
#   rails db:import_venues
#
# Le fichier CSV attendu : db/DB Etablissement.csv (séparateur : point-virgule)
# Les données proviennent du fichier des équipements sportifs (RES) du ministère.
# ─────────────────────────────────────────────────────────────────────────────
namespace :db do
  desc "Importe les établissements sportifs depuis db/DB Etablissement.csv"
  task import_venues: :environment do
    # Chemin vers le fichier CSV
    csv_file = Rails.root.join("db", "DB Etablissement.csv")

    unless File.exist?(csv_file)
      puts "❌ Fichier introuvable : #{csv_file}"
      exit 1
    end

    puts "🏟️  Début de l'import des établissements sportifs..."

    # Vider la table avant de réimporter pour éviter les doublons
    Venue.delete_all
    puts "🗑️  Table venues vidée."

    # Compteurs pour le suivi
    total     = 0
    imported  = 0
    skipped   = 0

    # Batch : on accumule des lignes et on insère par paquets de 1000
    # pour ne pas surcharger la mémoire avec 387 000 lignes
    batch_size = 1000
    batch      = []

    # Timestamp commun pour toutes les lignes (Rails l'exige pour created_at/updated_at)
    now = Time.current

    # "bom|UTF-8" : supprime automatiquement le BOM (﻿) en début de fichier.
    # Sans ça, la 1ère colonne s'appelle "﻿Nom de l'installation sportive" (avec BOM)
    # au lieu de "Nom de l'installation sportive" → name est importé nil.
    CSV.foreach(csv_file, headers: true, col_sep: ";", encoding: "bom|UTF-8") do |row|
      total += 1

      # Récupérer la longitude et la latitude
      lon = row["Longitude"].to_f
      lat = row["Latitude"].to_f

      # Ignorer les lignes sans coordonnées GPS valides
      if lon.zero? || lat.zero?
        skipped += 1
        next
      end

      # Construire le hash à insérer
      batch << {
        name: row["Nom de l'installation sportive"]&.strip,
        sport_type: row["Type d'équipement sportif"]&.strip,
        city: row["Commune nom"]&.strip,
        address: row["Adresse"]&.strip,
        postal_code: row["Code Postal"]&.strip,
        longitude: lon,
        latitude: lat,
        created_at: now,
        updated_at: now
      }

      imported += 1

      # Quand le batch est plein, on insère en base et on vide le tableau
      if batch.size >= batch_size
        Venue.insert_all(batch)
        batch = []
        print "." # Affiche un point pour montrer la progression
        $stdout.flush
      end
    end

    # Insérer le dernier batch (lignes restantes < 1000)
    Venue.insert_all(batch) if batch.any?

    puts "\n✅ Import terminé !"
    puts "   Total lignes lues   : #{total}"
    puts "   Établissements importés : #{imported}"
    puts "   Lignes ignorées (GPS manquant) : #{skipped}"
  end
end
