# Espace admin — consultation de la waitlist pré-lancement.
# Hérite de Admin::BaseController qui vérifie que l'utilisateur est admin.
module Admin
  class WaitlistEntriesController < Admin::BaseController
    # GET /admin/waitlist_entries
    # Affiche tous les emails inscrits, du plus récent au plus ancien.
    def index
      @waitlist_entries = WaitlistEntry.order(created_at: :desc)
      @total_count      = @waitlist_entries.count
    end

    # POST /admin/waitlist_entries/send_launch_email
    # Envoie l'email d'annonce de lancement à TOUS les inscrits de la waitlist.
    # Chaque email est envoyé en arrière-plan via deliver_later (Solid Queue)
    # pour ne pas bloquer la requête HTTP sur les grosses listes.
    def send_launch_email
      entries = WaitlistEntry.order(created_at: :desc)

      # Enfile un job d'envoi par email — Solid Queue les traite en parallèle
      entries.each do |entry|
        WaitlistMailer.launch_announcement(entry.email).deliver_later
      end

      # Flash avec le nombre d'emails enfilés pour confirmer à l'admin
      redirect_to admin_waitlist_entries_path,
                  notice: "#{entries.count} email#{entries.count > 1 ? 's' : ''} de lancement enfilé#{entries.count > 1 ? 's' : ''} dans la queue — ils partent dans quelques secondes."
    end
  end
end
