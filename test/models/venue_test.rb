require "test_helper"

# Tests du modèle Venue.
# Un Venue représente un établissement sportif (terrain, salle, etc.).
# Champs obligatoires : name et city.
# Scopes :
#   - in_city(city) → filtre par ville (insensible à la casse, LIKE)
#   - by_sport(sport) → filtre par type de sport (ILIKE)
class VenueTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un venue avec name et city est valide
  def test_venue_valide_avec_name_et_city
    venue = Venue.new(name: "Stade du Test", city: "Paris")
    assert venue.valid?, "Un venue avec name et city doit être valide"
  end

  # Cas d'erreur : le name est obligatoire
  def test_venue_invalide_sans_name
    venue = Venue.new(name: nil, city: "Paris")
    refute venue.valid?, "Un venue sans name doit être invalide"
    assert_includes venue.errors[:name], "ne peut pas être vide"
  end

  # Cas d'erreur : la city est obligatoire
  def test_venue_invalide_sans_city
    venue = Venue.new(name: "Stade Sans Ville", city: nil)
    refute venue.valid?, "Un venue sans city doit être invalide"
    assert_includes venue.errors[:city], "ne peut pas être vide"
  end

  # Edge case : les deux champs vides rendent le venue invalide avec deux erreurs
  def test_venue_invalide_si_tout_est_vide
    venue = Venue.new
    refute venue.valid?, "Un venue sans aucun champ doit être invalide"
    assert venue.errors[:name].any?, "Une erreur sur :name doit être présente"
    assert venue.errors[:city].any?, "Une erreur sur :city doit être présente"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : in_city filtre par ville de façon insensible à la casse
  def test_scope_in_city_retourne_les_venues_de_la_ville
    # Crée deux venues dans des villes différentes
    Venue.create!(name: "Terrain A", city: "Paris")
    Venue.create!(name: "Terrain B", city: "Lyon")

    result = Venue.in_city("Paris")
    # Seul le venue de Paris doit apparaître
    assert result.any? { |v| v.name == "Terrain A" }, "in_city('Paris') doit retourner le venue de Paris"
    assert result.none? { |v| v.name == "Terrain B" }, "in_city('Paris') ne doit pas retourner le venue de Lyon"
  end

  # Edge case : in_city est insensible à la casse (ILIKE en PostgreSQL)
  def test_scope_in_city_insensible_a_la_casse
    Venue.create!(name: "Terrain Casse", city: "Bordeaux")
    # Cherche avec une casse différente → doit quand même trouver
    result = Venue.in_city("bordeaux")
    assert result.any? { |v| v.name == "Terrain Casse" },
           "in_city doit être insensible à la casse (ILIKE)"
  end

  # Cas nominal : by_sport filtre par type de sport
  def test_scope_by_sport_retourne_les_venues_du_sport
    Venue.create!(name: "Court Tennis", city: "Paris", sport_type: "tennis")
    Venue.create!(name: "Terrain Foot", city: "Paris", sport_type: "football")

    result = Venue.by_sport("tennis")
    assert result.any? { |v| v.name == "Court Tennis" }, "by_sport('tennis') doit retourner le court de tennis"
    assert result.none? { |v| v.name == "Terrain Foot" }, "by_sport('tennis') ne doit pas retourner le terrain de foot"
  end

  # Edge case : in_city avec un terme partiel (LIKE %paris%) doit fonctionner
  def test_scope_in_city_accepte_terme_partiel
    Venue.create!(name: "Salle Nord", city: "Paris 18e")
    # "Paris" est contenu dans "Paris 18e" → doit être retourné
    result = Venue.in_city("Paris")
    assert result.any? { |v| v.name == "Salle Nord" },
           "in_city doit trouver les villes contenant le terme cherché"
  end
end
