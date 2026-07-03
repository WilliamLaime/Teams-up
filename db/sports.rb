# ─────────────────────────────────────────────────────────────────────────────
# Sports disponibles dans l'application.
#
# Ce fichier est chargé :
#   - par `db/seeds.rb` (seed complet de dev / `rails db:seed`)
#   - par la tâche `rails db:seed_sports` (jouée à chaque déploiement via
#     bin/docker-entrypoint) pour que tout nouveau sport remonte en prod.
#
# Pour ajouter un sport :
#   1. Ajouter une entrée dans SPORTS ci-dessous (name, icon, slug).
#   2. Ajouter ses images de couverture dans SportImagesHelper.
#   3. Déployer — le sport est seedé automatiquement.
# ─────────────────────────────────────────────────────────────────────────────
SPORTS = [
  { name: "Football",   icon: "⚽", slug: "football"   },
  { name: "Tennis",     icon: "🎾", slug: "tennis"     },
  { name: "Padel",      icon: "https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061667/sports/misc/padel.png", slug: "padel" },
  { name: "Volleyball", icon: "🏐", slug: "volleyball" },
  { name: "Basketball", icon: "🏀", slug: "basketball" },
  { name: "Handball",   icon: "🤾", slug: "handball"   },
  { name: "Badminton",  icon: "🏸", slug: "badminton"  },
  { name: "Ping-Pong",  icon: "🏓", slug: "ping-pong"  }
].freeze

# Insère les sports manquants de façon idempotente.
# Clé d'unicité : le slug (jamais de doublon si la tâche est rejouée).
def seed_sports
  SPORTS.each do |sport|
    Sport.find_or_create_by!(slug: sport[:slug]) do |s|
      s.name = sport[:name]
      s.icon = sport[:icon]
    end
  end
  puts "✅ #{Sport.count} sports en base."
end
