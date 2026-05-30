require "test_helper"

# Tests du modèle ContactMessage.
# Représente un message envoyé via le formulaire de contact public.
# Pas de relation avec User — n'importe qui peut envoyer.
# Tous les champs sont obligatoires : prenom, nom, email, sujet, message.
# L'email est validé avec ValidEmail2 (format + DNS MX record).
# Note : example.com n'a PAS de MX record → valid_mx? retourne false.
#        On utilise gmail.com qui a un MX record valide et connu.
class ContactMessageTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Attributs valides pour construire un ContactMessage de base.
  # gmail.com a un MX record valide → valid_mx? = true en environnement connecté.
  VALID_ATTRS = {
    prenom:  "Alice",
    nom:     "Martin",
    email:   "alice@gmail.com", # gmail.com a un MX record réel → valid_mx? = true
    sujet:   "Question sur le service",
    message: "Bonjour, j'ai une question."
  }.freeze

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS — champs obligatoires
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : tous les champs remplis avec un email valide → le message est valide
  def test_contact_message_valide_avec_tous_les_champs
    msg = ContactMessage.new(VALID_ATTRS)
    # On utilise valid? sans save pour ne pas déclencher les broadcasts ActionCable
    assert msg.valid?, "Un ContactMessage complet doit être valide : #{msg.errors.full_messages}"
  end

  # Cas d'erreur : le prénom est obligatoire
  def test_invalide_sans_prenom
    msg = ContactMessage.new(VALID_ATTRS.merge(prenom: nil))
    refute msg.valid?, "Un ContactMessage sans prénom doit être invalide"
    assert_includes msg.errors[:prenom], "ne peut pas être vide"
  end

  # Cas d'erreur : le nom est obligatoire
  def test_invalide_sans_nom
    msg = ContactMessage.new(VALID_ATTRS.merge(nom: nil))
    refute msg.valid?, "Un ContactMessage sans nom doit être invalide"
    assert_includes msg.errors[:nom], "ne peut pas être vide"
  end

  # Cas d'erreur : l'email est obligatoire
  def test_invalide_sans_email
    msg = ContactMessage.new(VALID_ATTRS.merge(email: nil))
    refute msg.valid?, "Un ContactMessage sans email doit être invalide"
    assert_includes msg.errors[:email], "ne peut pas être vide"
  end

  # Cas d'erreur : le sujet est obligatoire
  def test_invalide_sans_sujet
    msg = ContactMessage.new(VALID_ATTRS.merge(sujet: nil))
    refute msg.valid?, "Un ContactMessage sans sujet doit être invalide"
    assert_includes msg.errors[:sujet], "ne peut pas être vide"
  end

  # Cas d'erreur : le message est obligatoire
  def test_invalide_sans_message
    msg = ContactMessage.new(VALID_ATTRS.merge(message: nil))
    refute msg.valid?, "Un ContactMessage sans contenu de message doit être invalide"
    assert_includes msg.errors[:message], "ne peut pas être vide"
  end

  # Cas d'erreur : un email avec un format invalide (sans @) est rejeté
  def test_invalide_avec_email_mal_formate
    # ValidEmail2 rejette les adresses sans @ ou mal formées
    msg = ContactMessage.new(VALID_ATTRS.merge(email: "pas-un-email"))
    refute msg.valid?, "Un email mal formaté doit invalider le ContactMessage"
    assert msg.errors[:email].any?, "Une erreur sur :email doit être présente"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le scope unread retourne uniquement les messages non lus (lu: false).
  # On bypasse les validations avec save(validate: false) pour éviter le DNS lookup
  # de ValidEmail2 (valid_mx? fait un appel réseau — non fiable en CI/offline).
  def test_scope_unread_retourne_les_messages_non_lus
    lu_false = ContactMessage.new(VALID_ATTRS.merge(lu: false))
    lu_false.save(validate: false) # bypass le DNS lookup valid_mx?

    lu_true = ContactMessage.new(VALID_ATTRS.merge(email: "bob@gmail.com", lu: true))
    lu_true.save(validate: false)

    result = ContactMessage.unread
    assert_includes result, lu_false, "Le scope unread doit inclure les messages non lus"
    assert_not_includes result, lu_true, "Le scope unread ne doit pas inclure les messages déjà lus"
  end

  # Cas nominal : le scope recent trie du plus récent au plus ancien.
  # On bypasse les validations avec save(validate: false) pour éviter le DNS lookup.
  def test_scope_recent_trie_du_plus_recent_au_plus_ancien
    older = ContactMessage.new(VALID_ATTRS.merge(created_at: 2.days.ago))
    older.save(validate: false)

    newer = ContactMessage.new(VALID_ATTRS.merge(email: "newer@gmail.com", created_at: 1.day.ago))
    newer.save(validate: false)

    result = ContactMessage.recent
    # Le premier élément doit être le plus récent (newer)
    assert_equal newer.id, result.first.id, "Le scope recent doit placer le message le plus récent en premier"
  end
end
