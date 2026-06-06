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
        # Recharge la liste pour réafficher la page avec l'erreur inline
        @waitlist_entries = WaitlistEntry.order(created_at: :desc)
        @total_count      = @waitlist_entries.count
        # Affiche l'erreur en flash pour rester simple (pas de turbo frame)
        redirect_to admin_waitlist_entries_path,
                    alert: "Erreur : #{@new_entry.errors.full_messages.join(', ')}"
      end
    end
  end
end
