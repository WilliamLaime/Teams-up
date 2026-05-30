require "test_helper"

# Tests du modèle PushSubscription.
# Ce modèle stocke les subscriptions Web Push d'un utilisateur (un abonnement par appareil/navigateur).
# On vérifie les validations de présence et d'unicité de l'endpoint par user.
class PushSubscriptionTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  teardown { teardown_db }

  # ─── Helper ─────────────────────────────────────────────────────────────────

  # Crée et retourne un utilisateur de test avec profil.
  def make_user(email)
    create_test_user(email: email, first_name: "Push", last_name: "User")
  end

  # Retourne un hash d'attributs valides pour PushSubscription.
  # On génère un endpoint unique pour éviter les conflits entre tests.
  def valid_attrs(user, overrides = {})
    {
      user:     user,
      endpoint: "https://push.example.com/#{SecureRandom.hex(8)}",
      p256dh:   "BNcRdreALRFXTkOOUHK1EtK2wtZ_MjVt0bCGM3L4oaFYDV5ADrLW3FjS0IEoRWxbAfpFSnFe4J44MTGPQ0_g",
      auth:     "Kz9gB-yJCxqsqr9UH9gp3A"
    }.merge(overrides)
  end

  # ─── Validations : présence ──────────────────────────────────────────────────

  # Cas nominal : tous les attributs présents → valide.
  test "subscription valide avec tous les attributs" do
    user = make_user("valid_push@example.com")
    sub  = PushSubscription.new(valid_attrs(user))
    assert sub.valid?, "Attendu valide, erreurs : #{sub.errors.full_messages}"
  end

  # Cas d'erreur : endpoint absent → invalide.
  test "endpoint absent rend la subscription invalide" do
    user = make_user("no_endpoint@example.com")
    sub  = PushSubscription.new(valid_attrs(user, endpoint: ""))
    assert sub.invalid?
    assert sub.errors[:endpoint].any?
  end

  # Cas d'erreur : p256dh absent → invalide.
  test "p256dh absent rend la subscription invalide" do
    user = make_user("no_p256dh@example.com")
    sub  = PushSubscription.new(valid_attrs(user, p256dh: ""))
    assert sub.invalid?
    assert sub.errors[:p256dh].any?
  end

  # Cas d'erreur : auth absent → invalide.
  test "auth absent rend la subscription invalide" do
    user = make_user("no_auth@example.com")
    sub  = PushSubscription.new(valid_attrs(user, auth: ""))
    assert sub.invalid?
    assert sub.errors[:auth].any?
  end

  # ─── Validation : unicité de l'endpoint par user ─────────────────────────────

  # Cas d'erreur : deux subscriptions avec le même endpoint pour le même user → invalide.
  # C'est la validation uniqueness: { scope: :user_id }.
  test "endpoint en doublon pour le même user est invalide" do
    user     = make_user("dup_push@example.com")
    endpoint = "https://push.example.com/fixed_endpoint"

    PushSubscription.create!(valid_attrs(user, endpoint: endpoint))

    dup = PushSubscription.new(valid_attrs(user, endpoint: endpoint))
    assert dup.invalid?
    assert dup.errors[:endpoint].any?
  end

  # Cas nominal : le même endpoint peut être utilisé par deux users différents.
  # L'unicité est scopée à user_id → deux users peuvent avoir le même endpoint.
  test "le même endpoint est valide pour deux users différents" do
    user1    = make_user("user1_push@example.com")
    user2    = make_user("user2_push@example.com")
    endpoint = "https://push.example.com/shared_endpoint"

    PushSubscription.create!(valid_attrs(user1, endpoint: endpoint))

    sub2 = PushSubscription.new(valid_attrs(user2, endpoint: endpoint))
    assert sub2.valid?, "Le même endpoint est valide pour un autre user"
  end

  # ─── Association ─────────────────────────────────────────────────────────────

  # Vérifie que la subscription est bien liée à son user.
  test "belongs_to user fonctionne" do
    user = make_user("assoc_push@example.com")
    sub  = PushSubscription.create!(valid_attrs(user))
    assert_equal user.id, sub.user_id
  end
end
