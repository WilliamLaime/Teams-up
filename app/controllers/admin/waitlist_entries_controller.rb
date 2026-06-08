# Espace admin — consultation et gestion de la waitlist pré-lancement.
# Hérite de Admin::BaseController qui vérifie que l'utilisateur est admin.
module Admin
  class WaitlistEntriesController < Admin::BaseController
    # GET /admin/waitlist_entries
    # Affiche tous les emails inscrits, du plus récent au plus ancien.
    def index
      @waitlist_entries = WaitlistEntry.order(created_at: :desc)
      @total_count      = @waitlist_entries.count
      # Compteurs pour les badges et le bouton d'envoi
      @sent_count       = WaitlistEntry.where.not(launch_email_sent_at: nil).count
      @pending_count    = WaitlistEntry.where(launch_email_sent_at: nil).count
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
    # Envoie l'email de lancement uniquement aux inscrits qui ne l'ont pas encore reçu
    # (launch_email_sent_at IS NULL). Marque chaque entrée après envoi réussi.
    # Respecte la limite Resend de 5 req/s avec une pause toutes les 4 requêtes.
    def send_launch_email
      # On ne cible que les inscrits sans email envoyé — évite les doublons
      entries = WaitlistEntry.where(launch_email_sent_at: nil).order(created_at: :desc)
      sent    = 0
      errors  = []

      entries.each_with_index do |entry, index|
        # Pause toutes les 4 requêtes pour respecter la limite Resend (5 req/s)
        sleep(1.1) if index > 0 && index % 4 == 0

        # Envoi immédiat via l'API Resend
        WaitlistMailer.launch_announcement(entry.email).deliver_now

        # Horodate l'envoi pour ne pas renvoyer à cette personne si on relance
        entry.update_column(:launch_email_sent_at, Time.current)
        sent += 1
      rescue => e
        error_msg = "#{entry.email} : #{e.class} — #{e.message}"
        Rails.logger.error("[WaitlistMailer] Échec envoi — #{error_msg}")
        errors << error_msg
      end

      if errors.any?
        redirect_to admin_waitlist_entries_path,
                    alert: "#{sent} envoyé(s), #{errors.count} échec(s) : #{errors.first}"
      else
        redirect_to admin_waitlist_entries_path,
                    notice: "#{sent} email#{sent > 1 ? 's' : ''} envoyé#{sent > 1 ? 's' : ''} avec succès."
      end
    end
  end
end
