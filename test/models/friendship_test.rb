require "test_helper"

# Tests du modèle Friendship.
# Une Friendship représente la relation entre deux utilisateurs :
#   - user    : celui qui envoie la demande
#   - friend  : celui qui la reçoit
#   - status  : "pending" | "accepted" | "declined"
# Règles :
#   - On ne peut pas s'ajouter soi-même
#   - Le statut doit appartenir à STATUSES
class FriendshipTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée deux utilisateurs distincts pour les tests
  def setup_users
    user_a = create_test_user(email: "userA@example.com", first_name: "Alice", last_name: "A")
    user_b = create_test_user(email: "userB@example.com", first_name: "Bob",   last_name: "B")
    [user_a, user_b]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une friendship avec un statut valide doit être valide
  def test_friendship_valide_avec_statut_pending
    user_a, user_b = setup_users
    friendship = Friendship.new(user: user_a, friend: user_b, status: "pending")
    assert friendship.valid?, "Une friendship pending valide doit passer les validations"
  end

  # Cas d'erreur : un statut hors de la liste autorisée est rejeté
  def test_friendship_invalide_avec_statut_inconnu
    user_a, user_b = setup_users
    friendship = Friendship.new(user: user_a, friend: user_b, status: "blocked")
    refute friendship.valid?, "Un statut inconnu ('blocked') doit invalider la friendship"
    # La traduction du message "inclusion" n'est pas définie en fr → on vérifie juste la présence d'erreur
    assert friendship.errors[:status].any?, "Une erreur sur :status doit être présente pour un statut inconnu"
  end

  # Cas d'erreur : on ne peut pas s'ajouter soi-même comme ami
  def test_cannot_friend_yourself
    user_a = create_test_user(email: "solo@example.com", first_name: "Solo", last_name: "User")
    # On essaie de créer une friendship où user == friend → doit être invalide
    friendship = Friendship.new(user: user_a, friend: user_a, status: "pending")
    refute friendship.valid?, "On ne peut pas s'ajouter soi-même comme ami"
    assert_includes friendship.errors[:friend_id], "Vous ne pouvez pas vous ajouter vous-même"
  end

  # Edge case : chaque statut valide est accepté individuellement
  def test_tous_les_statuts_valides_sont_acceptes
    user_a, user_b = setup_users
    # "pending", "accepted", "declined" sont les 3 statuts autorisés
    Friendship::STATUSES.each do |statut|
      friendship = Friendship.new(user: user_a, friend: user_b, status: statut)
      assert friendship.valid?, "Le statut '#{statut}' doit être considéré comme valide"
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le scope pending retourne uniquement les demandes en attente
  def test_scope_pending_retourne_les_friendships_pending
    user_a, user_b = setup_users
    # Crée une friendship pending et une friendship acceptée
    f_pending  = Friendship.create!(user: user_a, friend: user_b, status: "pending")
    user_c = create_test_user(email: "userC@example.com", first_name: "Charlie", last_name: "C")
    Friendship.create!(user: user_a, friend: user_c, status: "accepted")

    result = Friendship.pending
    # Seule la friendship pending doit apparaître dans le scope
    assert_includes result, f_pending, "Le scope pending doit inclure les friendships en attente"
    # La friendship acceptée ne doit pas apparaître
    assert_equal 1, result.where(user: user_a).count,
                 "Le scope pending ne doit retourner que les friendships pending de user_a"
  end

  # Cas nominal : le scope accepted retourne uniquement les friendships acceptées
  def test_scope_accepted_retourne_les_friendships_acceptees
    user_a, user_b = setup_users
    f_accepted = Friendship.create!(user: user_a, friend: user_b, status: "accepted")

    result = Friendship.accepted
    assert_includes result, f_accepted, "Le scope accepted doit inclure les friendships acceptées"
  end

  # Cas nominal : le scope declined retourne uniquement les friendships refusées
  def test_scope_declined_retourne_les_friendships_declined
    user_a, user_b = setup_users
    f_declined = Friendship.create!(user: user_a, friend: user_b, status: "declined")

    result = Friendship.declined
    assert_includes result, f_declined, "Le scope declined doit inclure les friendships refusées"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES D'INSTANCE
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : pending? retourne true pour une friendship en attente
  def test_pending_retourne_true_si_statut_pending
    user_a, user_b = setup_users
    f = Friendship.new(user: user_a, friend: user_b, status: "pending")
    assert f.pending?, "pending? doit retourner true quand status == 'pending'"
  end

  # Cas d'erreur : pending? retourne false si le statut est différent
  def test_pending_retourne_false_si_statut_different
    user_a, user_b = setup_users
    f = Friendship.new(user: user_a, friend: user_b, status: "accepted")
    refute f.pending?, "pending? doit retourner false quand status != 'pending'"
  end

  # Cas nominal : accepted? retourne true pour une friendship acceptée
  def test_accepted_retourne_true_si_statut_accepted
    user_a, user_b = setup_users
    f = Friendship.new(user: user_a, friend: user_b, status: "accepted")
    assert f.accepted?, "accepted? doit retourner true quand status == 'accepted'"
  end

  # Cas nominal : declined? retourne true pour une friendship refusée
  def test_declined_retourne_true_si_statut_declined
    user_a, user_b = setup_users
    f = Friendship.new(user: user_a, friend: user_b, status: "declined")
    assert f.declined?, "declined? doit retourner true quand status == 'declined'"
  end
end
