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
    # La validation d'unicité et de format est gérée par le modèle WaitlistEntry.
    def create
      @new_entry = WaitlistEntry.new(email: params.dig(:waitlist_entry, :email))

      if @new_entry.save
        redirect_to admin_waitlist_entries_path,
                    notice: "#{@new_entry.email} ajouté à la waitlist."
      else
        # Affiche l'erreur en flash pour rester simple (pas de turbo frame)
        redirect_to admin_waitlist_entries_path,
                    alert: "Erreur : #{@new_entry.errors.full_messages.join(', ')}"
      end
    end

    # POST /admin/waitlist_entries/send_launch_email
    # Envoie l'email d'annonce de lancement à TOUS les inscrits de la waitlist.
    # On utilise deliver_now (synchrone) plutôt que deliver_later pour éviter
    # la dépendance à Solid Queue qui nécessite SOLID_QUEUE_IN_PUMA=true sur Railway.
    # L'envoi est séquentiel mais rapide (~1s par email via SendGrid).
    def send_launch_email
      entries = WaitlistEntry.order(created_at: :desc)
      sent    = 0

      entries.each do |entry|
        # deliver_now envoie immédiatement via SMTP SendGrid sans passer par la queue
        WaitlistMailer.launch_announcement(entry.email).deliver_now
        sent += 1
      rescue => e
        # Log l'erreur sans interrompre l'envoi aux autres destinataires
        Rails.logger.error("[WaitlistMailer] Échec envoi à #{entry.email} : #{e.class} — #{e.message}")
      end

      redirect_to admin_waitlist_entries_path,
                  notice: "#{sent} email#{sent > 1 ? 's' : ''} de lancement envoyé#{sent > 1 ? 's' : ''} avec succès."
    end
  end
end
