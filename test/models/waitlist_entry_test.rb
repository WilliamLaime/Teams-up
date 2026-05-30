require "test_helper"

# Tests du modèle WaitlistEntry.
# Stocke les emails des visiteurs en liste d'attente.
# Règles :
#   - Email obligatoire, format valide, unique
#   - Email normalisé en minuscules avant validation (before_validation callback)
class WaitlistEntryTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un email valide doit créer une entrée sans erreur
  def test_waitlist_entry_valide_avec_email
    entry = WaitlistEntry.new(email: "alice@example.com")
    assert entry.valid?, "Un email valide doit produire une entrée valide"
  end

  # Cas d'erreur : l'email est obligatoire
  def test_invalide_sans_email
    entry = WaitlistEntry.new(email: nil)
    refute entry.valid?, "Une entrée sans email doit être invalide"
    # L'app est configurée en français → le message est traduit
    assert entry.errors[:email].any?, "Une erreur sur :email doit être présente quand email est nil"
  end

  # Cas d'erreur : un email mal formaté (sans @) est rejeté
  def test_invalide_avec_email_mal_formate
    entry = WaitlistEntry.new(email: "pas-un-email")
    refute entry.valid?, "Un email mal formaté doit être invalide"
    assert entry.errors[:email].any?, "Une erreur sur :email doit être présente"
  end

  # Cas d'erreur : deux entrées avec le même email (même en casse différente) sont interdites
  def test_invalide_si_email_duplique
    WaitlistEntry.create!(email: "alice@example.com")
    doublon = WaitlistEntry.new(email: "alice@example.com")
    refute doublon.valid?, "Deux entrées avec le même email doivent être invalides"
    assert doublon.errors[:email].any?, "Une erreur d'unicité sur :email doit être présente"
  end

  # Edge case : l'unicité est insensible à la casse (case_sensitive: false)
  def test_unicite_insensible_a_la_casse
    WaitlistEntry.create!(email: "alice@example.com")
    # Même email en majuscules → doit être rejeté car normalisé en minuscules
    doublon = WaitlistEntry.new(email: "ALICE@EXAMPLE.COM")
    refute doublon.valid?,
           "L'unicité doit être insensible à la casse (avant_validation normalise en minuscules)"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # CALLBACK : normalisation de l'email en minuscules
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'email en majuscules est normalisé en minuscules avant sauvegarde
  def test_email_normalise_en_minuscules_avant_sauvegarde
    # On soumet un email en majuscules
    entry = WaitlistEntry.create!(email: "ALICE@EXAMPLE.COM")
    # Après sauvegarde, l'email doit être en minuscules
    assert_equal "alice@example.com", entry.email,
                 "Le callback before_validation doit normaliser l'email en minuscules"
  end

  # Edge case : les espaces autour de l'email sont supprimés (strip)
  def test_email_avec_espaces_est_strip
    entry = WaitlistEntry.new(email: "  alice@example.com  ")
    # before_validation fait un strip + downcase
    entry.valid? # déclenche le callback
    assert_equal "alice@example.com", entry.email,
                 "Les espaces en début et fin d'email doivent être supprimés"
  end
end
