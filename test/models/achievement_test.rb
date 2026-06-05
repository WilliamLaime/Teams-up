require "test_helper"

# Tests du modèle Achievement.
# Ce modèle stocke les badges/récompenses débloquables par les joueurs.
# On vérifie les validations et la constante CATEGORIES.
class AchievementTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # ─── Helper ────────────────────────────────────────────────────────────────

  # Retourne un Achievement valide — on génère une clé unique pour éviter
  # les conflits si le test est réexécuté ou si d'autres tests ajoutent des achievements.
  def valid_achievement(overrides = {})
    {
      key:        "test_achievement_#{SecureRandom.hex(4)}",
      name:       "Premier Match",
      xp_reward:  50
    }.merge(overrides)
  end

  # ─── Validations : key ─────────────────────────────────────────────────────

  # Cas nominal : un achievement avec key, name et xp_reward est valide.
  test "achievement valide avec tous les attributs" do
    a = Achievement.new(valid_achievement)
    assert a.valid?, "Attendu valide, erreurs : #{a.errors.full_messages}"
  end

  # Cas d'erreur : key absent → invalide.
  test "key absent rend l achievement invalide" do
    a = Achievement.new(valid_achievement(key: ""))
    assert a.invalid?
    assert a.errors[:key].any?
  end

  # Cas d'erreur : key en double → invalide (validates uniqueness).
  test "key en doublon rend l achievement invalide" do
    fixed_key = "doublon_#{SecureRandom.hex(4)}"
    Achievement.create!(valid_achievement(key: fixed_key))
    a = Achievement.new(valid_achievement(key: fixed_key))
    assert a.invalid?
    assert a.errors[:key].any?
  end

  # ─── Validations : name ────────────────────────────────────────────────────

  # Cas d'erreur : name absent → invalide.
  test "name absent rend l achievement invalide" do
    a = Achievement.new(valid_achievement(name: ""))
    assert a.invalid?
    assert a.errors[:name].any?
  end

  # ─── Validations : xp_reward ───────────────────────────────────────────────

  # Cas nominal : xp_reward à 0 est accepté (seuil >= 0).
  test "xp_reward a 0 est valide" do
    a = Achievement.new(valid_achievement(xp_reward: 0))
    assert a.valid?
  end

  # Cas d'erreur : xp_reward négatif → invalide.
  test "xp_reward negatif rend l achievement invalide" do
    a = Achievement.new(valid_achievement(xp_reward: -1))
    assert a.invalid?
    assert a.errors[:xp_reward].any?
  end

  # ─── Constante CATEGORIES ──────────────────────────────────────────────────

  # Vérifie que CATEGORIES contient les 3 catégories attendues.
  # Si quelqu'un modifie la liste, ce test échouera et alertera l'équipe.
  test "CATEGORIES contient match social et profile" do
    assert_includes Achievement::CATEGORIES, "match"
    assert_includes Achievement::CATEGORIES, "social"
    assert_includes Achievement::CATEGORIES, "profile"
  end

  # ─── Associations ──────────────────────────────────────────────────────────

  # Cas nominal : un achievement peut avoir plusieurs UserAchievement liés.
  test "has_many user_achievements" do
    a = Achievement.create!(valid_achievement)
    assert_respond_to a, :user_achievements
  end
end
