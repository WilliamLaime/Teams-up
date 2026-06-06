require "test_helper"

# Tests pour AccountDeletionMailer
# Ce mailer envoie une confirmation RGPD (art. 17 — droit à l'oubli) après
# la suppression d'un compte. Il reçoit des scalaires car le User est déjà
# détruit quand cet email est envoyé (impossible d'utiliser l'AR object).
class AccountDeletionMailerTest < ActionMailer::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)

  setup do
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
  end

  # ── CAS NOMINAL ──────────────────────────────────────────────────────────────

  # Vérifie que l'email de confirmation de suppression est envoyé à la bonne adresse
  # avec le bon sujet et les données scalaires attendues.
  test "account_deleted envoie l'email à l'adresse du compte supprimé" do
    user_email = "ancien.compte@test.com"
    user_name  = "Alice Test"
    deleted_at = Time.current

    email = AccountDeletionMailer.account_deleted(
      user_email: user_email,
      user_name:  user_name,
      deleted_at: deleted_at
    )

    # L'email doit être adressé à l'ancien propriétaire du compte
    assert_equal [user_email], email.to

    # Le sujet doit confirmer la suppression du compte
    assert_includes email.subject, "supprimé"
    assert_includes email.subject, "Team-Up"
  end

  # ── CAS LIMITE : NOM AFFICHÉ = EMAIL (user sans prénom/nom) ──────────────────

  # Vérifie que le mailer fonctionne quand user_name est l'email de l'utilisateur
  # (cas où le profil n'avait pas de prénom/nom renseigné).
  test "account_deleted fonctionne quand user_name est un email" do
    user_email = "sans.nom@test.com"

    assert_nothing_raised do
      email = AccountDeletionMailer.account_deleted(
        user_email: user_email,
        user_name:  user_email,   # display_name retourne l'email quand pas de profil
        deleted_at: Time.current
      )
      email.deliver_now
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  # ── CAS LIMITE : DELIVERED_NOW ───────────────────────────────────────────────

  # Vérifie l'envoi effectif via deliver_now (simule le job SolidQueue qui
  # appelle deliver_now de façon asynchrone).
  test "account_deleted est bien ajouté à deliveries après deliver_now" do
    assert_emails 1 do
      AccountDeletionMailer.account_deleted(
        user_email: "test.deletion@test.com",
        user_name:  "Bob Supprimé",
        deleted_at: 1.minute.ago
      ).deliver_now
    end
  end
end
