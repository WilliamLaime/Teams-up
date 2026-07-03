# ─────────────────────────────────────────────────────────────────────────────
# Venues manuellement curés, absents du dataset gouvernemental (RES).
#
# Ce fichier est chargé automatiquement à la fin de `rails db:import_venues`
# pour que ces établissements survivent à chaque réimport du CSV.
#
# Pour ajouter un venue manquant :
#   1. Ajouter une entrée dans CUSTOM_VENUES ci-dessous.
#   2. Relancer `rails db:import_venues` (ou `rails db:seed_custom_venues`).
# ─────────────────────────────────────────────────────────────────────────────

CUSTOM_VENUES = [
  # ── Bordeaux Lac ────────────────────────────────────────────────────────────
  {
    name:           "4Padel Bordeaux Lac",
    sport_type:     "Court de padel",
    city:           "Bordeaux",
    address:        "9 Rue Dumont d'Urville Entrée A",
    postal_code:    "33300",
    latitude:       44.87985,
    longitude:      -0.55949,
    from_nominatim: false
  },
  {
    name:           "Le Five Bordeaux",
    sport_type:     "Terrain de football",
    city:           "Bordeaux",
    address:        "9-13 Rue Dumont d'Urville",
    postal_code:    "33300",
    latitude:       44.87985,
    longitude:      -0.55949,
    from_nominatim: false
  },

  # ── Bordeaux intra-muros ─────────────────────────────────────────────────
  {
    name:           "UCPA Sport Station Bordeaux",
    sport_type:     "Salle multisports",
    city:           "Bordeaux",
    address:        "10 Rue Charles Chaigneau",
    postal_code:    "33100",
    latitude:       44.83820,
    longitude:      -0.59170,
    from_nominatim: false
  },

  # ── Mérignac ────────────────────────────────────────────────────────────────
  {
    name:           "Big Padel Mérignac",
    sport_type:     "Court de padel",
    city:           "Mérignac",
    address:        "5 Rue Hipparque",
    postal_code:    "33700",
    latitude:       44.83040,
    longitude:      -0.66350,
    from_nominatim: false
  },

  # ── Cenon ────────────────────────────────────────────────────────────────────
  {
    name:           "Padel House Cenon",
    sport_type:     "Court de padel",
    city:           "Cenon",
    address:        "4 Rue du Professeur Langevin",
    postal_code:    "33150",
    latitude:       44.85830,
    longitude:      -0.52600,
    from_nominatim: false
  },

  # ── Sainte-Eulalie ───────────────────────────────────────────────────────────
  {
    name:           "MB Padel Sainte-Eulalie",
    sport_type:     "Court de padel",
    city:           "Sainte-Eulalie",
    address:        "18 Rue Claude Bernard",
    postal_code:    "33560",
    latitude:       44.91500,
    longitude:      -0.49200,
    from_nominatim: false
  },

  # ── Blanquefort ──────────────────────────────────────────────────────────────
  {
    name:           "Ginga Padel & Futsal",
    sport_type:     "Court de padel",
    city:           "Blanquefort",
    address:        "7 Rue Espagne",
    postal_code:    "33290",
    latitude:       44.90800,
    longitude:      -0.63400,
    from_nominatim: false
  },

  # ── Bordeaux Lac ────────────────────────────────────────────────────────────
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Bordeaux",
    address:        "9 Rue Dumont d'Urville",
    postal_code:    "33300",
    latitude:       44.8800467,
    longitude:      -0.5597128,
    from_nominatim: false
  },

  # ── Paris 14e ──────────────────────────────────────────────────────────────
  {
    name:           "Stade Élisabeth",
    sport_type:     "Stade multisports",
    city:           "Paris",
    address:        "7 Avenue Paul Appell",
    postal_code:    "75014",
    latitude:       48.8211520,
    longitude:      2.3286298,
    from_nominatim: false
  },

  # ── Réseau Hoops Factory (complexes de basketball indoor) ───────────────────
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Aubervilliers",
    address:        "3 Rue Pierre Larousse",
    postal_code:    "93300",
    latitude:       48.9046121,
    longitude:      2.3795189,
    from_nominatim: false
  },
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Mons-en-Baroeul",
    address:        "11 Rue Louis Braille",
    postal_code:    "59370",
    latitude:       50.6382862,
    longitude:      3.0963938,
    from_nominatim: false
  },
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Toulouse",
    address:        "2 Rue de l'Égalité",
    postal_code:    "31200",
    latitude:       43.6310235,
    longitude:      1.4124745,
    from_nominatim: false
  },
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Aubière",
    address:        "28 Rue des Sauzes",
    postal_code:    "63170",
    latitude:       45.7563234,
    longitude:      3.1331627,
    from_nominatim: false
  },
  {
    name:           "Hoops Factory",
    sport_type:     "Terrain de basketball",
    city:           "Saran",
    address:        "Rue de l'Ormeteau",
    postal_code:    "45770",
    latitude:       47.9448544,
    longitude:      1.8951436,
    from_nominatim: false
  }
].freeze

# Insère ou met à jour les venues custom de façon idempotente.
# Clé d'unicité : (name, city) — cohérent avec l'index en base.
def seed_custom_venues
  now = Time.current
  CUSTOM_VENUES.each do |attrs|
    Venue.find_or_create_by!(name: attrs[:name], city: attrs[:city]) do |v|
      v.assign_attributes(attrs.merge(created_at: now, updated_at: now))
    end
  end
  puts "✅ Venues custom insérés/vérifiés (#{CUSTOM_VENUES.size} établissements)."
end
