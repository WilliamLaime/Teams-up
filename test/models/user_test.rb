require "test_helper"

# Tests du modèle User.
# On vérifie les validations Devise (mot de passe complexe), les attributs virtuels
# first_name/last_name obligatoires à la création, la validation du genre,
# et toutes les méthodes d'instance (amis, rang, display_name).
class UserTest < ActiveSupport::TestCase

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Construit un User valide prêt à être sauvegardé.
  # confirmed_at renseigné pour court-circuiter le flow e-mail Devise dans les tests.
  def valid_user_attrs(overrides = {})
    {
      email:      "test_#{SecureRandom.hex(4)}@example.com",
      password:   "Password1!",   # respecte la regex : majuscule + chiffre + symbole
      first_name: "Alice",
      last_name:  "Dupont",
      confirmed_at: Time.current
    }.merge(overrides)
  end

  # Crée un User confirmé EN BASE avec son Profil associé.
  # On délègue au helper create_test_user (défini dans test_helper.rb) qui :
  #   1. appelle User.create! avec first_name/last_name (obligatoires on: :create)
  #   2. appelle user.create_profil! pour créer le Profil associé
  # Sans ça, user.profil est nil et les tests display_name/rank échouent.
  def create_user(overrides = {})
    attrs = valid_user_attrs(overrides)
    create_test_user(
      email:      attrs[:email],
      password:   attrs[:password],
      first_name: attrs[:first_name] || "Alice",
      last_name:  attrs[:last_name]  || "Dupont"
    )
  end

  # ─── Validations : mot de passe ─────────────────────────────────────────────

  # Cas nominal : un mot de passe conforme (majuscule + chiffre + symbole) est accepté.
  test "mot de passe valide avec majuscule, chiffre et symbole est accepté" do
    user = User.new(valid_user_attrs(password: "Secure1!"))
    # valid? déclenche les validations sans toucher la base
    assert user.valid?, "Attendu valide, erreurs : #{user.errors.full_messages}"
  end

  # Cas d'erreur : un mot de passe sans majuscule est rejeté.
  test "mot de passe sans majuscule est rejeté" do
    user = User.new(valid_user_attrs(password: "password1!"))
    assert user.invalid?
    assert user.errors[:password].any?, "Devrait avoir une erreur sur :password"
  end

  # Cas d'erreur : un mot de passe sans chiffre est rejeté.
  test "mot de passe sans chiffre est rejeté" do
    user = User.new(valid_user_attrs(password: "Password!"))
    assert user.invalid?
    assert user.errors[:password].any?
  end

  # Cas d'erreur : un mot de passe sans symbole est rejeté.
  test "mot de passe sans symbole est rejeté" do
    user = User.new(valid_user_attrs(password: "Password1"))
    assert user.invalid?
    assert user.errors[:password].any?
  end

  # ─── Validations : first_name / last_name (on: :create) ─────────────────────

  # Cas d'erreur : first_name vide est rejeté à la création.
  # Ces validations sont uniquement sur :create (on: :create).
  test "first_name vide est rejeté à la création" do
    user = User.new(valid_user_attrs(first_name: ""))
    # On force le contexte de création
    assert user.invalid?(:create)
    assert user.errors[:first_name].any?
  end

  # Cas d'erreur : last_name vide est rejeté à la création.
  test "last_name vide est rejeté à la création" do
    user = User.new(valid_user_attrs(last_name: ""))
    assert user.invalid?(:create)
    assert user.errors[:last_name].any?
  end

  # Cas nominal : first_name et last_name présents → création acceptée.
  test "first_name et last_name présents permettent la création" do
    user = User.new(valid_user_attrs)
    assert user.valid?(:create)
  end

  # ─── Validations : genre ────────────────────────────────────────────────────

  # Cas nominal : genre nil est autorisé (allow_nil: true pour les anciens comptes).
  test "genre nil est accepté" do
    user = User.new(valid_user_attrs(genre: nil))
    assert user.valid?
  end

  # Cas nominal : chaque valeur de GENRES est acceptée.
  test "genre femme est accepté" do
    user = User.new(valid_user_attrs(genre: "femme"))
    assert user.valid?
  end

  test "genre homme est accepté" do
    user = User.new(valid_user_attrs(genre: "homme"))
    assert user.valid?
  end

  test "genre autre est accepté" do
    user = User.new(valid_user_attrs(genre: "autre"))
    assert user.valid?
  end

  # Cas d'erreur : une valeur hors liste est rejetée.
  test "genre invalide est rejeté" do
    user = User.new(valid_user_attrs(genre: "alien"))
    assert user.invalid?
    assert user.errors[:genre].any?
  end

  # ─── Méthode friends_with? ──────────────────────────────────────────────────

  # Cas nominal : retourne vrai si l'amitié est acceptée dans le sens user → other.
  test "friends_with? retourne vrai si friendship accepted dans le sens direct" do
    alice = create_user(email: "alice_fw1@example.com")
    bob   = create_user(email: "bob_fw1@example.com")
    Friendship.create!(user: alice, friend: bob, status: "accepted")

    assert alice.friends_with?(bob), "Alice devrait être amie avec Bob"
  end

  # Cas nominal : retourne vrai si l'amitié est acceptée dans le sens inverse (other → user).
  test "friends_with? retourne vrai si friendship accepted dans le sens inverse" do
    alice = create_user(email: "alice_fw2@example.com")
    bob   = create_user(email: "bob_fw2@example.com")
    # C'est Bob qui a envoyé la demande à Alice
    Friendship.create!(user: bob, friend: alice, status: "accepted")

    assert alice.friends_with?(bob), "Alice devrait être amie avec Bob (sens inverse)"
  end

  # Cas d'erreur : retourne faux si la demande est seulement en attente.
  test "friends_with? retourne faux si friendship est pending" do
    alice = create_user(email: "alice_fw3@example.com")
    bob   = create_user(email: "bob_fw3@example.com")
    Friendship.create!(user: alice, friend: bob, status: "pending")

    assert_not alice.friends_with?(bob)
  end

  # Cas d'erreur : retourne faux s'il n'y a aucune relation.
  test "friends_with? retourne faux s'il n'y a aucune relation" do
    alice = create_user(email: "alice_fw4@example.com")
    bob   = create_user(email: "bob_fw4@example.com")

    assert_not alice.friends_with?(bob)
  end

  # ─── Méthode all_friends ────────────────────────────────────────────────────

  # Cas nominal : retourne les amis des deux sens (envoyées ET reçues).
  test "all_friends retourne les amis dans les deux sens" do
    alice = create_user(email: "alice_af@example.com")
    bob   = create_user(email: "bob_af@example.com")
    carol = create_user(email: "carol_af@example.com")

    # Alice a envoyé à Bob (accepted)
    Friendship.create!(user: alice, friend: bob,   status: "accepted")
    # Carol a envoyé à Alice (accepted)
    Friendship.create!(user: carol, friend: alice, status: "accepted")

    friends = alice.all_friends
    assert_includes friends, bob,   "Bob devrait être dans all_friends"
    assert_includes friends, carol, "Carol devrait être dans all_friends"
  end

  # Cas d'erreur : les demandes pending ne sont pas dans all_friends.
  test "all_friends n'inclut pas les friendships pending" do
    alice = create_user(email: "alice_af2@example.com")
    bob   = create_user(email: "bob_af2@example.com")
    Friendship.create!(user: alice, friend: bob, status: "pending")

    assert_empty alice.all_friends
  end

  # ─── Méthode pending_request_sent_to? ───────────────────────────────────────

  # Cas nominal : retourne vrai quand une demande pending a été envoyée.
  test "pending_request_sent_to? retourne vrai si demande pending envoyée" do
    alice = create_user(email: "alice_prs@example.com")
    bob   = create_user(email: "bob_prs@example.com")
    Friendship.create!(user: alice, friend: bob, status: "pending")

    assert alice.pending_request_sent_to?(bob)
  end

  # Cas d'erreur : retourne faux si la demande est accepted.
  test "pending_request_sent_to? retourne faux si friendship accepted" do
    alice = create_user(email: "alice_prs2@example.com")
    bob   = create_user(email: "bob_prs2@example.com")
    Friendship.create!(user: alice, friend: bob, status: "accepted")

    assert_not alice.pending_request_sent_to?(bob)
  end

  # ─── Méthode pending_request_from? ──────────────────────────────────────────

  # Cas nominal : retourne vrai quand une demande pending a été reçue.
  test "pending_request_from? retourne vrai si demande pending reçue" do
    alice = create_user(email: "alice_prf@example.com")
    bob   = create_user(email: "bob_prf@example.com")
    # Bob a envoyé à Alice
    Friendship.create!(user: bob, friend: alice, status: "pending")

    assert alice.pending_request_from?(bob)
  end

  # Cas d'erreur : retourne faux si aucune demande reçue de cet user.
  test "pending_request_from? retourne faux si aucune demande reçue" do
    alice = create_user(email: "alice_prf2@example.com")
    bob   = create_user(email: "bob_prf2@example.com")

    assert_not alice.pending_request_from?(bob)
  end

  # ─── Méthode display_name ───────────────────────────────────────────────────

  # Cas nominal : retourne "Prénom Nom" si le profil est renseigné.
  # create_user utilise create_test_user qui crée aussi le Profil → user.profil n'est pas nil.
  test "display_name retourne Prénom Nom si profil présent" do
    user = create_user(email: "display1@example.com", first_name: "Alice", last_name: "Dupont")
    assert_equal "Alice Dupont", user.display_name
  end

  # Cas d'erreur : retourne l'email si le profil n'a pas de nom renseigné.
  test "display_name retourne l'email si profil sans nom" do
    user = create_user(email: "display2@example.com", first_name: "Alice", last_name: "Dupont")
    # On vide le profil directement en base pour forcer le cas dégénéré.
    # update_columns contourne les validations → on peut mettre nil.
    user.profil.update_columns(first_name: nil, last_name: nil)
    user.reload

    assert_equal "display2@example.com", user.display_name
  end

  # ─── Méthode rank ───────────────────────────────────────────────────────────

  # rank dépend de profil.xp_level → on crée un user avec profil via create_test_user.
  # update_column(:xp_level, N) met à jour la valeur en base sans passer par les validations.
  test "rank retourne bronze pour xp_level 1" do
    user = create_user(email: "rank1@example.com", first_name: "R", last_name: "One")
    user.profil.update_column(:xp_level, 1)
    assert_equal "bronze", user.rank
  end

  test "rank retourne bronze pour xp_level 2" do
    user = create_user(email: "rank2@example.com", first_name: "R", last_name: "Two")
    user.profil.update_column(:xp_level, 2)
    assert_equal "bronze", user.rank
  end

  test "rank retourne silver pour xp_level 3" do
    user = create_user(email: "rank3@example.com", first_name: "R", last_name: "Three")
    user.profil.update_column(:xp_level, 3)
    assert_equal "silver", user.rank
  end

  test "rank retourne silver pour xp_level 4" do
    user = create_user(email: "rank4@example.com", first_name: "R", last_name: "Four")
    user.profil.update_column(:xp_level, 4)
    assert_equal "silver", user.rank
  end

  test "rank retourne gold pour xp_level 5" do
    user = create_user(email: "rank5@example.com", first_name: "R", last_name: "Five")
    user.profil.update_column(:xp_level, 5)
    assert_equal "gold", user.rank
  end

  test "rank retourne platinum pour xp_level 7" do
    user = create_user(email: "rank7@example.com", first_name: "R", last_name: "Seven")
    user.profil.update_column(:xp_level, 7)
    assert_equal "platinum", user.rank
  end

  test "rank retourne emerald pour xp_level 9" do
    user = create_user(email: "rank9@example.com", first_name: "R", last_name: "Nine")
    user.profil.update_column(:xp_level, 9)
    assert_equal "emerald", user.rank
  end

  # Edge case : rank retourne bronze si profil est nil (pas encore créé).
  test "rank retourne bronze si profil est nil" do
    user = create_user(email: "ranknil@example.com", first_name: "R", last_name: "Nil")
    # On détruit le profil pour simuler l'absence de données
    user.profil.destroy
    user.reload

    assert_equal "bronze", user.rank
  end
end
