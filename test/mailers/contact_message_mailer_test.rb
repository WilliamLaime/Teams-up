require "test_helper"

# Tests pour ContactMessageMailer
# Ce mailer envoie une réponse aux messages de contact reçus via le formulaire /contact.
# Il est utilisé depuis l'espace admin par un administrateur.
class ContactMessageMailerTest < ActionMailer::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  setup do
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    # ContactMessage n'est pas dans teardown_db, on le supprime manuellement
    ContactMessage.delete_all
  end

  # Helper : construit un ContactMessage en bypассant la validation DNS MX.
  # La validation email_valide_et_existant fait un lookup DNS réel qui échoue
  # sur des domaines fictifs (test.com, example.com). On la court-circuite
  # en instanciant sans validate: false (ContactMessage ne l'expose pas)
  # en stubant directement la méthode de validation privée.
  def build_contact_message(prenom:, nom:, email:, sujet:, message:)
    msg = ContactMessage.new(prenom: prenom, nom: nom, email: email,
                             sujet: sujet, message: message)
    # Court-circuite la validation DNS pour les tests (pas de réseau nécessaire)
    msg.define_singleton_method(:email_valide_et_existant) { nil }
    msg.save!
    msg
  end

  # ── CAS NOMINAL ──────────────────────────────────────────────────────────────

  # Vérifie que l'email de réponse est envoyé à l'expéditeur du message de contact
  # avec le bon sujet ("Re : <sujet original>").
  test "reply envoie l'email à l'expéditeur du message de contact" do
    # Crée un message de contact en bypassant la validation DNS réelle
    contact_message = build_contact_message(
      prenom:  "Jean",
      nom:     "Dupont",
      email:   "jean.dupont@example.com",
      sujet:   "Problème de connexion",
      message: "Je n'arrive pas à me connecter à mon compte."
    )

    reply_body = "Bonjour Jean, voici notre réponse à votre demande..."

    email = ContactMessageMailer.reply(contact_message, reply_body)

    # L'email doit être adressé à l'expéditeur du message de contact
    # Le format attendu est "Prénom Nom <email>"
    assert_includes email.to.first, contact_message.email

    # Le sujet doit être "Re : <sujet original>"
    assert_includes email.subject, "Re :"
    assert_includes email.subject, contact_message.sujet
  end

  # ── CAS LIMITE : SUJET AVEC CARACTÈRES SPÉCIAUX ──────────────────────────────

  # Vérifie que le mailer ne plante pas avec un sujet contenant des caractères spéciaux.
  test "reply gère un sujet avec des caractères spéciaux" do
    contact_message = build_contact_message(
      prenom:  "Marie-Claire",
      nom:     "O'Brien",
      email:   "marie@example.com",
      sujet:   "Question sur l'inscription & les règles",
      message: "Bonjour, j'ai une question."
    )

    assert_nothing_raised do
      email = ContactMessageMailer.reply(contact_message, "Notre réponse")
      email.deliver_now
    end

    # Un email doit avoir été envoyé
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  # ── CAS LIMITE : CORPS DE RÉPONSE VIDE ───────────────────────────────────────

  # Vérifie que le mailer ne plante pas si le corps de réponse est vide
  # (cas d'un admin qui envoie une réponse sans texte par erreur).
  test "reply ne plante pas avec un corps de réponse vide" do
    contact_message = build_contact_message(
      prenom:  "Pierre",
      nom:     "Martin",
      email:   "pierre@example.com",
      sujet:   "Autre question",
      message: "Question courte."
    )

    assert_nothing_raised do
      email = ContactMessageMailer.reply(contact_message, "")
      email.deliver_now
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
  end
end
