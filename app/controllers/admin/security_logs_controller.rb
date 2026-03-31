# Controller admin pour afficher les logs de sécurité.
# Accessible uniquement aux admins (protégé par Admin::BaseController).
# Permet de filtrer par type d'événement et par plage de dates.
module Admin
  class SecurityLogsController < Admin::BaseController
    # Pagy::Backend fournit la méthode `pagy()` pour paginer les résultats
    include Pagy::Backend

    def index
      # On part de tous les logs, triés du plus récent au plus ancien
      logs = SecurityLog.includes(:user).recent

      # ── Filtre par type d'événement ────────────────────────────────────────
      # params[:event_type] vient du formulaire de filtre dans la vue
      # .present? vérifie que la valeur n'est ni nil ni une chaîne vide
      if params[:event_type].present?
        logs = logs.by_type(params[:event_type])
      end

      # ── Filtre par date de début ────────────────────────────────────────────
      # beginning_of_day → 00:00:00 du jour sélectionné
      if params[:date_from].present?
        logs = logs.where("created_at >= ?", params[:date_from].to_date.beginning_of_day)
      end

      # ── Filtre par date de fin ──────────────────────────────────────────────
      # end_of_day → 23:59:59 du jour sélectionné
      if params[:date_to].present?
        logs = logs.where("created_at <= ?", params[:date_to].to_date.end_of_day)
      end

      # ── Pagination : 50 logs par page ──────────────────────────────────────
      # pagy retourne [objet_pagination, collection_paginée]
      @pagy, @security_logs = pagy(logs, limit: 50)

      # Liste des types pour le menu déroulant du filtre dans la vue
      @event_types = SecurityLog::EVENT_TYPES
    end
  end
end
