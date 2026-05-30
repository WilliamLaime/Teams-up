require "test_helper"

# Tests du modèle UserSport.
# Table de jointure entre User et Sport.
# Règle métier : un user ne peut pas s'inscrire deux fois au même sport.
class UserSportTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  teardown do
    # UserSport doit être supprimé avant User et Sport (contraintes FK des deux côtés)
    UserSport.delete_all
    teardown_db
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un Sport minimal valide.
  def make_sport(name = "Sport #{SecureRandom.hex(3)}")
    Sport.create!(name: name, icon: "⚽", slug: name.downcase.gsub(" ", "_"))
  end

  # Crée un User avec profil.
  def make_user(email)
    create_test_user(email: email, first_name: "Sport", last_name: "User")
  end

  # ─── Validation : unicité (user_id scoped à sport_id) ────────────────────────

  # Cas nominal : un user peut s'inscrire à un sport → valide.
  test "user_sport valide avec user et sport uniques" do
    user  = make_user("us_valid@example.com")
    sport = make_sport
    us    = UserSport.new(user: user, sport: sport)
    assert us.valid?, "Attendu valide, erreurs : #{us.errors.full_messages}"
  end

  # Cas d'erreur : un user ne peut pas s'inscrire deux fois au même sport.
  test "user_sport en doublon pour le même user et sport est invalide" do
    user  = make_user("us_dup@example.com")
    sport = make_sport

    UserSport.create!(user: user, sport: sport)

    dup = UserSport.new(user: user, sport: sport)
    assert dup.invalid?
    assert dup.errors[:user_id].any?, "L'erreur doit porter sur user_id (unicité scopée)"
  end

  # Cas nominal : deux users différents peuvent être inscrits au même sport.
  test "deux users différents peuvent avoir le même sport" do
    user1 = make_user("us_user1@example.com")
    user2 = make_user("us_user2@example.com")
    sport = make_sport

    UserSport.create!(user: user1, sport: sport)

    us2 = UserSport.new(user: user2, sport: sport)
    assert us2.valid?, "Le même sport peut être ajouté par un autre user"
  end

  # Cas nominal : un user peut être inscrit à plusieurs sports différents.
  test "un user peut avoir plusieurs sports différents" do
    user   = make_user("us_multi@example.com")
    sport1 = make_sport
    sport2 = make_sport

    UserSport.create!(user: user, sport: sport1)
    us2 = UserSport.new(user: user, sport: sport2)

    assert us2.valid?, "Un user peut s'inscrire à des sports différents"
  end

  # ─── Associations ────────────────────────────────────────────────────────────

  # Vérifie que les associations belongs_to sont bien définies.
  test "responds_to user et sport" do
    us = UserSport.new
    assert_respond_to us, :user
    assert_respond_to us, :sport
  end
end
