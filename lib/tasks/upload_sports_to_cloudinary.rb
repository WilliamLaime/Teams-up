# Script one-shot : upload les images sports vers Cloudinary
# Usage : rails runner lib/tasks/upload_sports_to_cloudinary.rb
#
# Ce script :
#   1. Prend chaque image .webp + png dans app/assets/images/sports/
#   2. L'upload sur Cloudinary dans le dossier "sports/"
#   3. Affiche le hash Ruby final à copier dans le helper

require "cloudinary"

# Dossier source local
BASE_DIR = Rails.root.join("app/assets/images/sports")

# Liste des images à uploader, organisée par sport
# (on ignore les sous-dossiers "originaux/" qui sont les fichiers source bruts)
SPORT_FILES = {
  "football"   => Dir[BASE_DIR.join("Football/*.webp")].sort,
  "tennis"     => Dir[BASE_DIR.join("Tennis/*.webp")].sort,
  "padel"      => Dir[BASE_DIR.join("Padel/*.webp")].sort,
  "volleyball" => Dir[BASE_DIR.join("Volley/*.webp")].sort,
  "basketball" => Dir[BASE_DIR.join("Basketball/*.webp")].sort,
  "handball"   => Dir[BASE_DIR.join("Handball/*.webp")].sort,
  "badminton"  => Dir[BASE_DIR.join("Badminton/*.webp")].sort,
  "misc"       => [
    BASE_DIR.join("multisports.png").to_s,
    BASE_DIR.join("multisports-img.png").to_s,
    BASE_DIR.join("padel.png").to_s
  ].select { |f| File.exist?(f) }
}

# Résultat final : { sport => [url1, url2, ...] }
result = {}

SPORT_FILES.each do |sport, files|
  puts "\n📤 Upload #{sport} (#{files.length} fichiers)..."
  result[sport] = []

  files.each do |file_path|
    # Nom du fichier sans extension (ex: "ballon")
    filename = File.basename(file_path, ".*")

    # Identifiant Cloudinary : "sports/football/ballon"
    public_id = "sports/#{sport}/#{filename}"

    begin
      # Upload vers Cloudinary — use_filename: true garde le nom d'origine
      response = Cloudinary::Uploader.upload(
        file_path,
        public_id: public_id,
        overwrite: false,   # ne re-uploade pas si déjà présent
        resource_type: "image"
      )

      url = response["secure_url"]
      result[sport] << url
      puts "  ✅ #{filename} → #{url}"

    rescue => e
      puts "  ❌ Erreur #{filename} : #{e.message}"
    end
  end
end

# Affichage du hash Ruby final à copier dans le helper
puts "\n\n" + "="*60
puts "HASH RUBY À COPIER DANS app/helpers/sport_images_helper.rb :"
puts "="*60
puts "SPORT_IMAGES = {"
result.each do |sport, urls|
  next if sport == "misc"
  puts "  \"#{sport}\" => %w["
  urls.each { |url| puts "    #{url}" }
  puts "  ],"
end
puts "}.freeze"

puts "\nURLs misc :"
(result["misc"] || []).each do |url|
  name = url.split("/").last.split("?").first
  puts "  #{name} => #{url}"
end
