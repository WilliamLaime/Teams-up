# Espace admin — consultation et gestion de la waitlist pré-lancement.
# Hérite de Admin::BaseController qui vérifie que l'utilisateur est admin.
module Admin
  class WaitlistEntriesController < Admin::BaseController
    # GET /admin/waitlist_entries
    # Affiche tous les emails inscrits, du plus récent au plus ancien.
    def index
      @waitlist_entries = WaitlistEntry.order(created_at: :desc)
      @total_count      = @waitlist_entries.count
      # Objet vide pour le formulaire d'ajout manuel sur la même page
      @new_entry        = WaitlistEntry.new
    end

    # POST /admin/waitlist_entries
    # Ajoute un email manuellement dans la waitlist depuis l'espace admin.
    def create
      @new_entry = WaitlistEntry.new(email: params.dig(:waitlist_entry, :email))

      if @new_entry.save
        redirect_to admin_waitlist_entries_path,
                    notice: "#{@new_entry.email} ajouté à la waitlist."
      else
        redirect_to admin_waitlist_entries_path,
                    alert: "Erreur : #{@new_entry.errors.full_messages.join(', ')}"
      end
    end

    # POST /admin/waitlist_entries/send_launch_email
    # Envoie l'email de lancement à tous les inscrits.
    # Utilise deliver_now (synchrone) pour éviter la dépendance à Solid Queue.
    # En cas d'erreur SMTP, affiche le message dans le flash pour débugger.
    def send_launch_email
      entries = WaitlistEntry.order(created_at: :desc)
      sent    = 0
      errors  = []

      entries.each do |entry|
        # deliver_now envoie immédiatement via SMTP SendGrid
        WaitlistMailer.launch_announcement(entry.email).deliver_now
        sent += 1
      rescue => e
        # On collecte l'erreur pour l'afficher dans le flash admin
        error_msg = "#{entry.email} : #{e.class} — #{e.message}"
        Rails.logger.error("[WaitlistMailer] Échec envoi — #{error_msg}")
        errors << error_msg
      end

      if errors.any?
        # Affiche les erreurs directement dans le flash pour les voir sans accès aux logs
        redirect_to admin_waitlist_entries_path,
                    alert: "#{sent} envoyé(s), #{errors.count} échec(s) : #{errors.first}"
      else
        redirect_to admin_waitlist_entries_path,
                    notice: "#{sent} email#{sent > 1 ? 's' : ''} envoyé#{sent > 1 ? 's' : ''} avec succès."
      end
    end
  end
end
