# lib/tasks/factory_reset.rake
#
# Remet la base de données dans un état "sortie d'usine" :
# supprime toutes les données de test en conservant uniquement
# les 4 comptes fondateurs et les données de référence (sports, venues).
#
# Usage : rails factory_reset:run
# Dry-run : rails factory_reset:run DRY_RUN=true

namespace :factory_reset do
  FOUNDER_EMAILS = %w[
    axel-bisson@hotmail.com
  ].freeze

  task run: :environment do
    dry_run = ENV["DRY_RUN"] == "true"

    puts ""
    puts "=================================================="
    puts "  FACTORY RESET — Teams-up"
    puts "  Mode : #{dry_run ? 'DRY RUN (aucune suppression réelle)' : 'PRODUCTION — données effacées définitivement'}"
    puts "=================================================="
    puts ""

    # Récupère les IDs des fondateurs à partir de leurs emails
    founder_users = User.where(email: FOUNDER_EMAILS)

    if founder_users.count != FOUNDER_EMAILS.size
      found     = founder_users.pluck(:email)
      not_found = FOUNDER_EMAILS - found
      abort "ERREUR : les emails suivants sont introuvables en base : #{not_found.join(', ')}"
    end

    founder_ids = founder_users.pluck(:id)
    founder_profil_ids = Profil.where(user_id: founder_ids).pluck(:id)

    puts "Fondateurs conservés (#{founder_users.count}) :"
    founder_users.each { |u| puts "  - #{u.email} (id=#{u.id})" }
    puts ""

    # ------------------------------------------------------------------
    # Comptage avant suppression (affiché même en dry-run)
    # ------------------------------------------------------------------
    counts = {
      "Users (hors fondateurs)" => User.where.not(id: founder_ids).count,
      "Matchs" => Match.count,
      "MatchUsers" => MatchUser.count,
      "MatchVotes" => MatchVote.count,
      "Teams" => Team.count,
      "TeamMembers" => TeamMember.count,
      "TeamInvitations" => TeamInvitation.count,
      "Messages (match)" => Message.where.not(match_id: nil).count,
      "Messages (team)" => Message.where.not(team_id: nil).count,
      "Messages (conversation privée)" => Message.where.not(private_conversation_id: nil).count,
      "PrivateConversations" => PrivateConversation.count,
      "Avis" => Avis.count,
      "Friendships" => Friendship.count,
      "Notifications" => Notification.count,
      "UserAchievements (fondateurs)" => UserAchievement.where(user_id: founder_ids).count,
      "SportProfils (fondateurs)" => SportProfil.where(profil_id: founder_profil_ids).count,
      "ProfilFavoriteVenues" => ProfilFavoriteVenue.count,
      "PushSubscriptions" => PushSubscription.count,
      "SecurityLogs" => SecurityLog.count,
      "ImageModerations" => ImageModeration.count,
      "ContactMessages" => ContactMessage.count,
      "WaitlistEntries" => WaitlistEntry.count,
      "Active Storage blobs orphelins" => ActiveStorage::Blob.unattached.count
    }

    puts "Données qui seront supprimées :"
    counts.each { |label, count| puts "  #{label.ljust(35)} #{count}" }
    puts ""

    if dry_run
      puts "DRY RUN — rien n'a été supprimé. Relance sans DRY_RUN=true pour exécuter."
      exit 0
    end

    # ------------------------------------------------------------------
    # Confirmation manuelle obligatoire en production
    # ------------------------------------------------------------------
    print "Tape CONFIRMER pour lancer la suppression définitive : "
    input = $stdin.gets.chomp
    abort "Annulé." unless input == "CONFIRMER"

    puts ""
    puts "Suppression en cours..."

    ActiveRecord::Base.transaction do
      # --- Blobs orphelins d'abord (avant de casser les attachments) ---
      puts "  Purge des blobs Active Storage orphelins..."
      ActiveStorage::Blob.unattached.find_each(&:purge)

      # --- Données liées aux matchs ---
      puts "  Suppression des votes de match..."
      MatchVote.delete_all

      puts "  Suppression des participants de match..."
      MatchUser.delete_all

      puts "  Suppression des messages de match..."
      Message.where.not(match_id: nil).delete_all

      puts "  Suppression des matchs..."
      Match.destroy_all # destroy_all pour déclencher les callbacks ActiveStorage

      # --- Données liées aux teams ---
      puts "  Suppression des invitations d'équipe..."
      TeamInvitation.delete_all

      puts "  Suppression des membres d'équipe..."
      TeamMember.delete_all

      puts "  Suppression des messages d'équipe..."
      Message.where.not(team_id: nil).delete_all

      puts "  Suppression des équipes..."
      Team.destroy_all

      # --- Conversations privées ---
      puts "  Suppression des messages privés..."
      Message.where.not(private_conversation_id: nil).delete_all

      puts "  Suppression des conversations privées..."
      PrivateConversation.delete_all

      # --- Relations sociales ---
      puts "  Suppression des avis..."
      Avis.delete_all

      puts "  Suppression des amitiés..."
      Friendship.delete_all

      # --- Notifications ---
      puts "  Suppression des notifications..."
      Notification.delete_all

      # --- Reset XP / achievements des fondateurs ---
      # (les stats seraient faussées par les matchs de test supprimés)
      puts "  Reset des achievements des fondateurs..."
      UserAchievement.where(user_id: founder_ids).delete_all

      puts "  Reset des sport_profils des fondateurs (niveau remis à nil)..."
      # level est nullable — nil = "non renseigné", valeur d'usine
      SportProfil.where(profil_id: founder_profil_ids).update_all(level: nil)

      # --- Préférences de lieux des fondateurs ---
      puts "  Suppression des profil_favorite_venues des fondateurs..."
      ProfilFavoriteVenue.where(profil_id: founder_profil_ids).delete_all

      # --- Push subscriptions ---
      puts "  Suppression des push subscriptions..."
      PushSubscription.delete_all

      # --- Security logs ---
      puts "  Suppression des security logs..."
      SecurityLog.delete_all

      # --- Image moderations ---
      puts "  Suppression des image moderations..."
      ImageModeration.delete_all

      # --- Contact messages & waitlist ---
      puts "  Suppression des contact messages..."
      ContactMessage.delete_all

      puts "  Suppression de la waitlist..."
      WaitlistEntry.delete_all

      # --- Suppression des users hors fondateurs ---
      # destroy_all pour purger leurs avatars Cloudinary via ActiveStorage callbacks
      puts "  Suppression des comptes non-fondateurs (+ avatars Cloudinary)..."
      User.where.not(id: founder_ids).destroy_all

      # --- Deuxième passe de blobs orphelins (avatars des users supprimés) ---
      puts "  Purge finale des blobs orphelins..."
      ActiveStorage::Blob.unattached.find_each(&:purge)
    end

    puts ""
    puts "=================================================="
    puts "  FACTORY RESET TERMINÉ"
    puts "  Base de données remise à zéro."
    puts "  #{founder_users.count} comptes fondateurs conservés."
    puts "=================================================="
  end
end
