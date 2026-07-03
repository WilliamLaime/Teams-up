# frozen_string_literal: true

# ──────────────────────────────────────────────────────────────────────────────
# Rake task : rails mailers:test_all
#
# Envoie un email de chaque type vers Mailtrap pour vérification visuelle.
# Utilise les premiers records en DB — à lancer en environnement dev avec des
# données seedées.
#
# Usage :
#   rails mailers:test_all              → envoie TOUS les mailers
#   rails mailers:test_all[devise]      → envoie uniquement les Devise mailers
#   rails mailers:test_all[user]        → envoie uniquement les UserMailer
#   rails mailers:test_all[waitlist]    → envoie uniquement WaitlistMailer
#   rails mailers:test_all[account]     → envoie uniquement AccountDeletionMailer
#   rails mailers:test_all[contact]     → envoie uniquement ContactMessageMailer
# ──────────────────────────────────────────────────────────────────────────────

namespace :mailers do
  desc "Envoie un email de test pour chaque mailer vers Mailtrap"
  task :test_all, [:group] => :environment do |_t, args|
    group = args[:group]&.downcase # nil = tous les groupes

    # ── Helpers ──────────────────────────────────────────────────────────────
    # Compteur d'emails envoyés et d'erreurs
    sent = 0
    errors = []

    # Envoi avec gestion d'erreur et log
    send_mail = lambda do |label, &block|
      print "  📧 #{label}..."
      mail = block.call
      mail.deliver_now
      sent += 1
      puts " ✅"
    rescue StandardError => e
      errors << { label: label, error: e.message }
      puts " ❌ #{e.message}"
    end

    # ── Données de test ──────────────────────────────────────────────────────
    # On récupère les premiers records existants en DB
    user1 = User.first
    user2 = User.second

    unless user1
      puts "❌ Aucun User en DB. Lance `rails db:seed` d'abord."
      exit 1
    end

    unless user2
      puts "❌ Il faut au moins 2 Users en DB. Lance `rails db:seed` d'abord."
      exit 1
    end

    match = Match.first
    puts "⚠️  Aucun Match en DB — les mailers liés aux matchs seront ignorés." unless match

    puts "\n🚀 Envoi des mailers de test...\n\n"

    # ── 1. Devise Mailers (6) ────────────────────────────────────────────────
    if group.nil? || group == "devise"
      puts "── Devise ──"

      # Génère un token de confirmation temporaire pour les mails Devise
      # qui en ont besoin (confirmation, reset password, unlock)
      raw_token = SecureRandom.hex(20)

      send_mail.call("Confirmation instructions") do
        Devise::Mailer.confirmation_instructions(user1, raw_token)
      end

      send_mail.call("Reset password instructions") do
        Devise::Mailer.reset_password_instructions(user1, raw_token)
      end

      send_mail.call("Password change") do
        Devise::Mailer.password_change(user1)
      end

      send_mail.call("Email changed") do
        Devise::Mailer.email_changed(user1)
      end

      send_mail.call("Unlock instructions") do
        Devise::Mailer.unlock_instructions(user1, raw_token)
      end

      puts ""
    end

    # ── 2. UserMailer (11) ───────────────────────────────────────────────────
    if group.nil? || group == "user"
      puts "── UserMailer ──"

      if match
        send_mail.call("match_created") do
          UserMailer.match_created(match)
        end

        send_mail.call("match_joined (approved)") do
          UserMailer.match_joined(match, user2, status: "approved")
        end

        # Pour match_status_changed, on a besoin d'un MatchUser
        match_user = match.match_users.first
        if match_user
          send_mail.call("match_status_changed (accepted)") do
            UserMailer.match_status_changed(match_user, accepted: true)
          end

          send_mail.call("match_status_changed (rejected)") do
            UserMailer.match_status_changed(match_user, accepted: false)
          end
        else
          puts "  ⏭️  match_status_changed — pas de MatchUser en DB, ignoré"
        end

        send_mail.call("match_cancelled") do
          UserMailer.match_cancelled(match, user2)
        end

        send_mail.call("match_cancelled_async") do
          UserMailer.match_cancelled_async(
            user_email: user2.email,
            match_title: match.title,
            match_date: match.date_match || Date.tomorrow,
            match_time_str: "19h30",
            venue_name: match.venue&.name || "Stade de test",
            venue_city: match.venue&.city || "Paris",
            organizer_name: match.user.display_name
          )
        end

        send_mail.call("match_player_left") do
          UserMailer.match_player_left(match, user2)
        end

        send_mail.call("match_modified") do
          UserMailer.match_modified(match, user2, changes: ["la date", "l'heure", "le lieu"])
        end

        send_mail.call("match_reminder") do
          UserMailer.match_reminder(match, user2)
        end
      else
        puts "  ⏭️  Tous les mailers match_* ignorés (pas de Match en DB)"
      end

      # avis_received — besoin d'un Avis en DB
      avis = defined?(Avis) ? Avis.first : nil
      if avis
        send_mail.call("avis_received") do
          UserMailer.avis_received(avis)
        end
      else
        puts "  ⏭️  avis_received — pas d'Avis en DB, ignoré"
      end

      # team_invitation_received — besoin d'une TeamInvitation en DB
      invitation = defined?(TeamInvitation) ? TeamInvitation.first : nil
      if invitation
        send_mail.call("team_invitation_received") do
          UserMailer.team_invitation_received(invitation)
        end
      else
        puts "  ⏭️  team_invitation_received — pas de TeamInvitation en DB, ignoré"
      end

      # friendship_decision
      send_mail.call("friendship_decision (accepted)") do
        UserMailer.friendship_decision(user1, user2, accepted: true)
      end

      send_mail.call("friendship_decision (rejected)") do
        UserMailer.friendship_decision(user1, user2, accepted: false)
      end

      puts ""
    end

    # ── 3. WaitlistMailer (1) ────────────────────────────────────────────────
    if group.nil? || group == "waitlist"
      puts "── WaitlistMailer ──"

      send_mail.call("launch_announcement") do
        WaitlistMailer.launch_announcement(user1.email)
      end

      puts ""
    end

    # ── 4. AccountDeletionMailer (1) ─────────────────────────────────────────
    if group.nil? || group == "account"
      puts "── AccountDeletionMailer ──"

      send_mail.call("account_deleted") do
        AccountDeletionMailer.account_deleted(
          user_email: user1.email,
          user_name: user1.display_name,
          deleted_at: Time.current
        )
      end

      puts ""
    end

    # ── 5. ContactMessageMailer (1) ──────────────────────────────────────────
    if group.nil? || group == "contact"
      puts "── ContactMessageMailer ──"

      # On cherche un ContactMessage existant ou on en crée un mock
      contact = ContactMessage.first
      if contact
        send_mail.call("reply") do
          ContactMessageMailer.reply(contact, "Merci pour votre message ! Ceci est un test.")
        end
      else
        # Crée un ContactMessage temporaire en mémoire (sans sauvegarder)
        contact = ContactMessage.new(
          prenom: "Jean",
          nom: "Test",
          email: user1.email,
          sujet: "Question de test",
          message: "Ceci est un message de test."
        )
        send_mail.call("reply (mock contact)") do
          ContactMessageMailer.reply(contact, "Merci pour votre message ! Ceci est un test.")
        end
      end

      puts ""
    end

    # ── Résumé ───────────────────────────────────────────────────────────────
    puts "═" * 50
    puts "📊 Résumé : #{sent} email(s) envoyé(s)"
    if errors.any?
      puts "⚠️  #{errors.size} erreur(s) :"
      errors.each { |e| puts "   - #{e[:label]} : #{e[:error]}" }
    else
      puts "✅ Aucune erreur !"
    end
    puts "═" * 50
    puts "\n👉 Vérifie dans Mailtrap : https://mailtrap.io/inboxes\n\n"
  end
end
