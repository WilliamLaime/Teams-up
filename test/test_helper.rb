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

    # ─── Helper : faire gagner un match de tournoi via un vrai score ────────────
    # Depuis le Lot 4, le vainqueur est DÉRIVÉ du score set-par-set (plus de
    # winner_id posé à la main). Construit un score « sec » (best_of sets gagnés
    # d'affilée) pour `winner`, conforme aux règles du sport, puis sauvegarde.
    # Lit les règles SUR LE MATCH et non sur le sport : TournamentMatch#scoring_rules
    # durcit le best_of en phase finale quand le sport le prévoit (ping-pong : 3
    # manches gagnantes en poule, 4 en phase finale). Passer par le sport
    # produirait un score de 3 manches sur un match qui en exige 4 — le vainqueur
    # ne serait pas dérivé et le match resterait `pending`, silencieusement.
    def win_tournament_match!(match, winner)
      rules  = match.scoring_rules
      needed = match.sets_to_win
      set    = winner.id == match.player_a_id ? [rules[:target], 0] : [0, rules[:target]]
      match.assign_score(Array.new(needed) { set.dup })
      match.save!
      match
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
      # Les messages couvrent les 4 types : match, équipe, conversation privée,
      # match de tournoi
      Message.delete_all
      Notification.delete_all
      MatchUser.delete_all
      Match.delete_all
      # Tournois : les matchs référencent les inscriptions (player_a/b/winner) et
      # les rondes → vider matchs → rondes → inscriptions → tournois, puis avant
      # User/Sport pour éviter les violations de FK.
      # Les accusés de lecture du chat référencent le match ET l'utilisateur :
      # à vider avant les deux.
      TournamentMatchChatRead.delete_all
      TournamentMatch.delete_all
      TournamentRound.delete_all
      TournamentUser.delete_all
      Tournament.delete_all
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
