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
  end
end
