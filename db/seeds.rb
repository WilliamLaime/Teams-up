# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ── Sports de base ────────────────────────────────────────────────────────────
# find_or_create_by! = idempotent (peut être relancé sans créer de doublons)
puts "Création des sports..."

sports_data = [
  { name: "Football",   icon: "⚽", slug: "football"   },
  { name: "Tennis",     icon: "🎾", slug: "tennis"     },
  { name: "Padel",      icon: "sports/padel.png", slug: "padel"      },
  { name: "Volleyball", icon: "🏐", slug: "volleyball" },
  { name: "Basketball", icon: "🏀", slug: "basketball" },
  { name: "Handball",   icon: "🤾", slug: "handball"   },
  { name: "Badminton",  icon: "🏸", slug: "badminton"  }
]

sports_data.each do |sport|
  Sport.find_or_create_by!(slug: sport[:slug]) do |s|
    s.name = sport[:name]
    s.icon = sport[:icon]
  end
end

puts "✅ #{Sport.count} sports créés."

# Assigne Football à tous les matchs existants sans sport (migration de données)
football = Sport.find_by(slug: "football")
if football
  updated = Match.where(sport_id: nil).update_all(sport_id: football.id)
  puts "⚽ #{updated} matchs existants tagués Football." if updated > 0
end
