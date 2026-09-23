require "test_helper"

# Tests du mail récapitulatif des messages de chat (ChatMailer#new_messages).
class ChatMailerTest < ActionMailer::TestCase
  teardown { teardown_db }

  setup do
    @alice = create_test_user(email: "mailer-alice@example.com", first_name: "Alice", last_name: "Martin")
    @bob   = create_test_user(email: "mailer-bob@example.com", first_name: "Bob", last_name: "Durand")
    @conversation = PrivateConversation.between(@alice, @bob)
  end

  def build_mail(*contents)
    messages = contents.map { |content| @conversation.messages.create!(user: @alice, content: content) }
    digest = ChatEmailDigest.find_by!(user: @bob, chattable: @conversation)
    ChatMailer.new_messages(digest, messages)
  end

  test "objet et destinataire d'une conversation privée" do
    mail = build_mail("Salut")

    assert_equal [@bob.email], mail.to
    assert_equal "💬 Nouveau message de Alice Martin", mail.subject
  end

  test "l'objet compte les messages regroupés" do
    assert_equal "💬 3 nouveaux messages de Alice Martin", build_mail("Salut", "tu joues", "samedi ?").subject
  end

  test "le bouton ouvre directement la conversation" do
    html = build_mail("Salut").html_part.body.to_s

    assert_includes html, "://example.com/users/#{@alice.id}/profil?open_chat=#{@conversation.id}"
  end

  test "le contenu d'un message est échappé (pas d'injection HTML)" do
    html = build_mail("<script>alert('x')</script>").html_part.body.to_s

    assert_not_includes html, "<script>alert"
    assert_includes html, "&lt;script&gt;"
  end

  test "lien et en-têtes de désinscription" do
    mail = build_mail("Salut")
    token = @bob.profil.signed_id(purpose: ChatEmailUnsubscribesController::TOKEN_PURPOSE)
    url = "https://example.com/notifications-email/desinscription/#{token}"

    assert_includes mail.html_part.body.to_s, url
    assert_equal "<#{url}>", mail["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
  end

  test "au-delà de 5 messages, seuls les plus récents sont recopiés" do
    contents = (1..7).map { |i| "Message numéro #{i}" }
    text = build_mail(*contents).text_part.body.to_s

    assert_includes text, "+ 2 message(s) plus ancien(s)"
    assert_includes text, "Message numéro 7"
    assert_not_includes text, "Message numéro 1\n"
  end
end
