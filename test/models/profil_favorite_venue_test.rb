require "test_helper"

# Tests du modèle ProfilFavoriteVenue.
# Table de jointure entre Profil et Venue.
# Règle métier : un profil ne peut pas ajouter deux fois le même lieu en favori.
class ProfilFavoriteVenueTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  teardown do
    # Nettoyage dans l'ordre FK
    ProfilFavoriteVenue.delete_all
    teardown_db
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un Venue minimal valide.
  def make_venue(name = "Venue #{SecureRandom.hex(3)}")
    Venue.create!(name: name, address: "1 rue du Sport", city: "Paris")
  end

  # Crée un User avec profil et retourne le profil.
  def make_profil(email)
    user = create_test_user(email: email, first_name: "Fav", last_name: "Venue")
    user.profil
  end

  # ─── Validation : unicité (profil_id scoped à venue_id) ──────────────────────

  # Cas nominal : un profil peut ajouter un lieu en favori → valide.
  test "profil_favorite_venue valide avec profil et venue uniques" do
    profil = make_profil("pfv_valid@example.com")
    venue  = make_venue
    pfv    = ProfilFavoriteVenue.new(profil: profil, venue: venue)
    assert pfv.valid?, "Attendu valide, erreurs : #{pfv.errors.full_messages}"
  end

  # Cas d'erreur : un profil ne peut pas ajouter deux fois le même lieu en favori.
  test "profil_favorite_venue en doublon est invalide" do
    profil = make_profil("pfv_dup@example.com")
    venue  = make_venue

    ProfilFavoriteVenue.create!(profil: profil, venue: venue)

    dup = ProfilFavoriteVenue.new(profil: profil, venue: venue)
    assert dup.invalid?
    assert dup.errors[:profil_id].any?, "L'erreur doit porter sur profil_id (unicité scopée)"
  end

  # Cas nominal : deux profils différents peuvent ajouter le même lieu en favori.
  test "deux profils différents peuvent avoir le même venue en favori" do
    profil1 = make_profil("pfv_user1@example.com")
    profil2 = make_profil("pfv_user2@example.com")
    venue   = make_venue

    ProfilFavoriteVenue.create!(profil: profil1, venue: venue)

    pfv2 = ProfilFavoriteVenue.new(profil: profil2, venue: venue)
    assert pfv2.valid?, "Le même venue peut être en favori pour un autre profil"
  end

  # Cas nominal : un profil peut avoir plusieurs venues favoris différents.
  test "un profil peut avoir plusieurs venues différents en favori" do
    profil = make_profil("pfv_multi@example.com")
    venue1 = make_venue
    venue2 = make_venue

    ProfilFavoriteVenue.create!(profil: profil, venue: venue1)
    pfv2 = ProfilFavoriteVenue.new(profil: profil, venue: venue2)

    assert pfv2.valid?, "Un profil peut avoir plusieurs venues favoris différents"
  end

  # ─── Associations ────────────────────────────────────────────────────────────

  # Vérifie que les associations belongs_to sont bien définies.
  test "responds_to profil et venue" do
    pfv = ProfilFavoriteVenue.new
    assert_respond_to pfv, :profil
    assert_respond_to pfv, :venue
  end
end
