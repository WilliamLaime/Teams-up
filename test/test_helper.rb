ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Lancer les tests en parallèle (un process par CPU)
    parallelize(workers: :number_of_processors)

    # Charger toutes les fixtures par défaut (utilisées par les tests de policies existants)
    fixtures :all

    # ─── Helper : créer un utilisateur complet ──────────────────────────────────
    # Problème : first_name et last_name sont des attr_accessor sur User (validés
    # uniquement à la création, on: :create). Le Profil n'est PAS créé
    # automatiquement — c'est le RegistrationsController qui le fait.
    # Dans les tests, on doit donc : (1) passer first_name/last_name à User.create!
    # puis (2) créer le Profil manuellement avec create_profil!
    def create_test_user(email:, password: "Test1234!", first_name: "Test", last_name: "User", **attrs)
      user = User.create!(
        email: email,
        password: password,
        confirmed_at: Time.current,
        first_name: first_name,
        last_name: last_name,
        **attrs
      )
      # Le Profil doit être créé séparément — il n'existe pas de after_create callback
      user.create_profil!(first_name: first_name, last_name: last_name)
      user
    end

    # ─── Helper : teardown complet dans l'ordre FK ──────────────────────────────
    # PostgreSQL vérifie les contraintes FK : on doit supprimer les tables
    # enfants avant les tables parentes pour éviter PG::ForeignKeyViolation.
    # Ordre complet :
    #   votes/avis → messages → notifications → match_users → matchs
    #   → amis → invitations/membres → équipes → sport_profils → profils
    #   → private_conversations (FK sender_id + recipient_id NOT NULL vers users)
    #   → user_sports (table jointure User ↔ Sport)
    #   → push_subscriptions (FK user_id vers users)
    #   → users → sports → venues
    def teardown_db
      MatchVote.delete_all
      Avis.delete_all
      # Les messages couvrent les 3 types : match, équipe, conversation privée
      Message.delete_all
      Notification.delete_all
      MatchUser.delete_all
      Match.delete_all
      Friendship.delete_all
      TeamMember.delete_all
      TeamInvitation.delete_all
      Team.delete_all
      SportProfil.delete_all
      Profil.delete_all
      # private_conversations a sender_id et recipient_id NOT NULL vers users
      # → doit être supprimé AVANT les users
      PrivateConversation.delete_all
      # user_sports est une table de jointure User ↔ Sport (créée par sports << sport)
      # Doit être vidée AVANT users et sports (contraintes FK sur les deux colonnes)
      UserSport.delete_all
      # push_subscriptions référence users via FK — doit être supprimé avant users
      PushSubscription.delete_all
      User.delete_all
      Sport.delete_all
      Venue.delete_all
    end
  end
end
