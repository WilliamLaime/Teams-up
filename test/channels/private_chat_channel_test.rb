require "test_helper"

# Tests du channel PrivateChatChannel.
# Ce channel gère les notifications de frappe ("typing...") dans une conversation privée.
#
# Comportements testés :
#   - Le sender peut s'abonner → stream créé
#   - Le recipient peut s'abonner → stream créé
#   - Un tiers non impliqué est rejeté
#   - Une conversation inexistante entraîne un reject
#   - La méthode #typing diffuse le nom de l'utilisateur sur le stream
class PrivateChatChannelTest < ActionCable::Channel::TestCase
  parallelize(workers: 1)

  # teardown_db gère l'ordre complet des FK (inclut PrivateConversation, Friendship, etc.)
  teardown { teardown_db }

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un User avec profil complet.
  def make_user(email, first_name: "Private", last_name: "Chat")
    create_test_user(email: email, first_name: first_name, last_name: last_name)
  end

  # Crée une PrivateConversation entre deux utilisateurs.
  def make_conversation(sender, recipient)
    PrivateConversation.create!(sender: sender, recipient: recipient)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # #subscribed
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le sender peut s'abonner à la conversation privée.
  test "subscribes le sender et crée le stream" do
    sender    = make_user("sender_pc@example.com", first_name: "Sender", last_name: "PC")
    recipient = make_user("recipient_pc@example.com", first_name: "Recip", last_name: "PC")
    convo     = make_conversation(sender, recipient)

    stub_connection current_user: sender
    subscribe(conversation_id: convo.id)

    assert subscription.confirmed?,
           "Le sender doit pouvoir s'abonner à la conversation"
    assert_has_stream "private_chat_typing_#{convo.id}"
  end

  # Cas nominal : le recipient peut s'abonner à la conversation privée.
  test "subscribes le recipient et crée le stream" do
    sender    = make_user("sender2_pc@example.com")
    recipient = make_user("recipient2_pc@example.com")
    convo     = make_conversation(sender, recipient)

    stub_connection current_user: recipient
    subscribe(conversation_id: convo.id)

    assert subscription.confirmed?,
           "Le recipient doit pouvoir s'abonner à la conversation"
    assert_has_stream "private_chat_typing_#{convo.id}"
  end

  # Cas d'erreur : un tiers (ni sender ni recipient) est rejeté.
  test "rejette un utilisateur tiers non impliqué dans la conversation" do
    sender    = make_user("sender3_pc@example.com")
    recipient = make_user("recipient3_pc@example.com")
    outsider  = make_user("outsider_pc@example.com")
    convo     = make_conversation(sender, recipient)

    # outsider n'est ni sender ni recipient → participant? retourne false → reject
    stub_connection current_user: outsider
    subscribe(conversation_id: convo.id)

    assert subscription.rejected?,
           "Un tiers doit être rejeté"
  end

  # Cas d'erreur : un conversation_id inexistant entraîne un reject.
  test "rejette si le conversation_id est inexistant" do
    user = make_user("no_convo_pc@example.com")

    stub_connection current_user: user
    subscribe(conversation_id: 999999)

    assert subscription.rejected?,
           "Un conversation_id inexistant doit entraîner un reject"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # #typing
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : typing diffuse le display_name de l'utilisateur sur le stream.
  test "typing diffuse le nom de l'utilisateur sur le stream de la conversation" do
    sender    = make_user("typing_sender_pc@example.com", first_name: "Typeur", last_name: "Privé")
    recipient = make_user("typing_recip_pc@example.com")
    convo     = make_conversation(sender, recipient)

    stub_connection current_user: sender
    subscribe(conversation_id: convo.id)

    assert_broadcasts("private_chat_typing_#{convo.id}", 1) do
      perform :typing, {}
    end
  end
end
