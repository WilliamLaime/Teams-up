require "test_helper"

# Tests de FriendshipPolicy — vérifie qui peut créer, accepter, refuser ou
# supprimer une relation d'amitié.
#
# Vocabulaire de la relation :
#   - record.user   → celui qui a ENVOYÉ la demande (l'initiateur)
#   - record.friend → celui qui a REÇU la demande (le destinataire)
#
# Règles testées :
#   create?  → il faut être connecté
#   destroy? → l'initiateur peut toujours supprimer ; le destinataire uniquement si accepted
#   accept?  → uniquement le destinataire
#   decline? → uniquement le destinataire
class FriendshipPolicyTest < ActiveSupport::TestCase
  def setup
    @initiator   = users(:one)  # a envoyé la demande
    @recipient   = users(:two)  # a reçu la demande

    # Friendship en attente (l'initiateur attend la réponse du destinataire)
    @pending_friendship = friendships(:pending_one_to_two)
  end

  # ── create? ───────────────────────────────────────────────────────────────

  # Cas nominal : un utilisateur connecté peut envoyer une demande d'ami
  def test_create_autorise_pour_user_connecte
    assert FriendshipPolicy.new(@initiator, @pending_friendship).create?,
           "Un utilisateur connecté doit pouvoir envoyer une demande d'ami"
  end

  # Cas d'erreur : un utilisateur non connecté ne peut pas envoyer de demande
  def test_create_interdit_pour_user_nil
    refute FriendshipPolicy.new(nil, @pending_friendship).create?,
           "Un utilisateur non connecté ne doit pas pouvoir envoyer une demande"
  end

  # ── destroy? ──────────────────────────────────────────────────────────────

  # L'initiateur peut toujours annuler sa demande, même si elle est encore pending
  def test_destroy_autorise_pour_initiateur
    assert FriendshipPolicy.new(@initiator, @pending_friendship).destroy?,
           "L'initiateur doit toujours pouvoir annuler/supprimer sa demande"
  end

  # Le destinataire NE PEUT PAS supprimer une friendship qui est encore "pending"
  # (il doit d'abord accept?/decline? — pas destroy? directement)
  def test_destroy_interdit_pour_recipient_si_pending
    refute FriendshipPolicy.new(@recipient, @pending_friendship).destroy?,
           "Le destinataire ne doit pas pouvoir supprimer une friendship pending"
  end

  # Le destinataire PEUT supprimer une friendship qui a été acceptée
  # (il veut "retirer" l'ami après avoir accepté)
  def test_destroy_autorise_pour_recipient_si_accepted
    # On crée une friendship accepted en mémoire pour ce test
    accepted_friendship = Friendship.new(
      user:   @initiator,
      friend: @recipient,
      status: "accepted"
    )
    assert FriendshipPolicy.new(@recipient, accepted_friendship).destroy?,
           "Le destinataire doit pouvoir supprimer une amitié déjà acceptée"
  end

  # ── accept? ───────────────────────────────────────────────────────────────

  # Seul le destinataire peut accepter la demande d'ami
  def test_accept_autorise_pour_le_recipient
    assert FriendshipPolicy.new(@recipient, @pending_friendship).accept?,
           "Le destinataire doit pouvoir accepter la demande d'ami"
  end

  # L'initiateur ne peut pas accepter sa propre demande
  def test_accept_interdit_pour_l_initiateur
    refute FriendshipPolicy.new(@initiator, @pending_friendship).accept?,
           "L'initiateur ne doit pas pouvoir accepter sa propre demande"
  end

  # ── decline? ──────────────────────────────────────────────────────────────

  # Seul le destinataire peut refuser la demande d'ami
  def test_decline_autorise_pour_le_recipient
    assert FriendshipPolicy.new(@recipient, @pending_friendship).decline?,
           "Le destinataire doit pouvoir refuser la demande d'ami"
  end

  # L'initiateur ne peut pas refuser sa propre demande (il doit utiliser destroy?)
  def test_decline_interdit_pour_l_initiateur
    refute FriendshipPolicy.new(@initiator, @pending_friendship).decline?,
           "L'initiateur ne doit pas pouvoir refuser sa propre demande"
  end
end
