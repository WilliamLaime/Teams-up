require "test_helper"

# Tests du modèle UserAchievement.
# Table de jointure entre User et Achievement.
# Règle métier : un user ne peut débloquer le même achievement qu'une seule fois.
class UserAchievementTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  teardown do
    # UserAchievement doit être supprimé avant Achievement et User
    UserAchievement.delete_all
    Achievement.delete_all
    teardown_db
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  # Crée un Achievement valide avec une clé unique pour éviter les conflits.
  def make_achievement
    Achievement.create!(
      key:       "ua_test_#{SecureRandom.hex(4)}",
      name:      "Badge Test",
      xp_reward: 10
    )
  end

  # Crée un User avec profil.
  def make_user(email)
    create_test_user(email: email, first_name: "UA", last_name: "Test")
  end

  # ─── Validation : unicité (user_id scoped à achievement_id) ──────────────────

  # Cas nominal : un user peut débloquer un achievement → UserAchievement valide.
  test "user_achievement valide avec user et achievement uniques" do
    user        = make_user("ua_valid@example.com")
    achievement = make_achievement
    ua          = UserAchievement.new(user: user, achievement: achievement)
    assert ua.valid?, "Attendu valide, erreurs : #{ua.errors.full_messages}"
  end

  # Cas d'erreur : un user ne peut pas débloquer le même achievement deux fois.
  test "user_achievement en doublon pour le même user et achievement est invalide" do
    user        = make_user("ua_dup@example.com")
    achievement = make_achievement

    UserAchievement.create!(user: user, achievement: achievement)

    dup = UserAchievement.new(user: user, achievement: achievement)
    assert dup.invalid?
    assert dup.errors[:user_id].any?, "L'erreur doit porter sur user_id (unicité scopée)"
  end

  # Cas nominal : deux users différents peuvent débloquer le même achievement.
  test "deux users différents peuvent avoir le même achievement" do
    user1       = make_user("ua_user1@example.com")
    user2       = make_user("ua_user2@example.com")
    achievement = make_achievement

    UserAchievement.create!(user: user1, achievement: achievement)

    ua2 = UserAchievement.new(user: user2, achievement: achievement)
    assert ua2.valid?, "Le même achievement peut être débloqué par un autre user"
  end

  # Cas nominal : un user peut débloquer plusieurs achievements différents.
  test "un user peut avoir plusieurs achievements différents" do
    user         = make_user("ua_multi@example.com")
    achievement1 = make_achievement
    achievement2 = make_achievement

    UserAchievement.create!(user: user, achievement: achievement1)
    ua2 = UserAchievement.new(user: user, achievement: achievement2)

    assert ua2.valid?, "Un user peut débloquer des achievements différents"
  end

  # ─── Associations ────────────────────────────────────────────────────────────

  # Vérifie que les associations belongs_to sont bien définies.
  test "responds_to user et achievement" do
    ua = UserAchievement.new
    assert_respond_to ua, :user
    assert_respond_to ua, :achievement
  end
end
