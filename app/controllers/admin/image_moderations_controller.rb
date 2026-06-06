# Controller admin pour le suivi de la modération d'images IA.
# Hérite de Admin::BaseController — seuls les admins y ont accès.
#
# Affiche les KPIs (quota, rejets, erreurs) et le tableau détaillé de
# toutes les lignes ImageModeration avec filtres par statut et recherche.
module Admin
  class ImageModerationsController < Admin::BaseController
    include Pagy::Backend

    def index
      # ── KPIs ───────────────────────────────────────────────────────────────
      # Quota Sightengine : nombre d'appels ce mois / plafond free tier
      @quota_used  = ImageModeration.quota_used_this_month
      @quota_total = ImageModeration::MONTHLY_QUOTA
      @quota_alert = ImageModeration.quota_alert?

      # Compteurs par statut pour les badges en haut de page
      @count_pending  = ImageModeration.status_pending.count
      @count_approved = ImageModeration.status_approved.count
      @count_rejected = ImageModeration.status_rejected.count
      @count_errored  = ImageModeration.status_errored.count
      @count_total    = ImageModeration.count

      # Rejets récents pour les KPIs
      @rejected_today     = ImageModeration.rejected_today.count
      @rejected_this_week = ImageModeration.rejected_this_week.count

      # ── Tableau filtrable ──────────────────────────────────────────────────
      scope = ImageModeration.order(created_at: :desc).includes(:moderatable)

      # Filtre par statut (query param ?status=rejected)
      if params[:status].present? && ImageModeration.statuses.key?(params[:status])
        scope = scope.where(status: params[:status])
      end

      # Filtre par type de record (query param ?type=Profil ou ?type=Team)
      scope = scope.where(moderatable_type: params[:type]) if params[:type].present?

      @pagy, @moderations = pagy(scope, limit: 25)
    end
  end
end
