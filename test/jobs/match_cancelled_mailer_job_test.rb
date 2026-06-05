require "test_helper"

# Tests pour MatchCancelledMailerJob
# Ce job envoie l'email d'annulation d'un match à un joueur inscrit.
# Il accepte uniquement des données scalaires (String, Date) pour éviter
# les problèmes de désérialisation GlobalID quand le match est déjà supprimé.
class MatchCancelledMailerJobTest < ActiveJob::TestCase
  # Désactive la parallélisation pour éviter les deadlocks PostgreSQL
  # lors du chargement des fixtures dans plusieurs processus simultanés.
  parallelize(workers: 1)
  # Réinitialise la boîte mail avant chaque test
  setup do
    ActionMailer::Base.deliveries.clear
    # Livraison synchrone dans les tests pour capturer les emails avec deliveries
    ActionMailer::Base.delivery_method = :test
  end

  teardown { teardown_db }

  # ── CAS NOMINAL ──────────────────────────────────────────────────────────────

  # Vérifie que le job s'exécute sans erreur et envoie bien un email
  # avec les bonnes données scalaires (titre du match, date, organisateur...).
  test "envoie un email d'annulation avec les bonnes données scalaires" do
    # Le job attend des scalaires, pas des AR objects
    user_email     = "joueur@test.com"
    match_title    = "Match du samedi"
    match_date     = Date.tomorrow
    match_time_str = "15h00"
    venue_name     = "Stade Jean Bouin"
    venue_city     = "Paris"
    organizer_name = "Alice Test"

    # perform_now exécute le job de façon synchrone
    # et deliver_now dans le job place l'email dans ActionMailer::Base.deliveries
    assert_nothing_raised do
      MatchCancelledMailerJob.perform_now(
        user_email,
        match_title,
        match_date,
        match_time_str,
        venue_name,
        venue_city,
        organizer_name
      )
    end

    # Un email doit avoir été envoyé
    assert_equal 1, ActionMailer::Base.deliveries.size

    email = ActionMailer::Base.deliveries.last
    # L'email doit être adressé au bon destinataire
    assert_includes email.to, user_email
    # Le sujet doit contenir le titre du match
    assert_includes email.subject, match_title
  end

  # ── CAS LIMITE : CHAMPS OPTIONNELS NILS ──────────────────────────────────────

  # Vérifie que le job ne plante pas quand venue_name, venue_city
  # et match_time_str sont nil (champs optionnels).
  test "ne plante pas si venue_name, venue_city et match_time_str sont nil" do
    assert_nothing_raised do
      MatchCancelledMailerJob.perform_now(
        "joueur2@test.com",
        "Match sans lieu",
        Date.tomorrow,
        nil,   # match_time_str optionnel
        nil,   # venue_name optionnel
        nil,   # venue_city optionnel
        "Bob Test"
      )
    end

    # L'email doit quand même être envoyé
    assert_equal 1, ActionMailer::Base.deliveries.size
  end
end
