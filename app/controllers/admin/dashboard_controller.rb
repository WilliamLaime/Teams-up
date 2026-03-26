# Controller du tableau de bord admin.
# Hérite de Admin::BaseController — seuls les admins peuvent y accéder.
# Calcule tous les KPIs affichés sur le dashboard.
class Admin::DashboardController < Admin::BaseController
  def show
    # ── KPIs Utilisateurs ────────────────────────────────────────────────────
    # Nombre total d'utilisateurs inscrits
    @total_users = User.count

    # Nouveaux utilisateurs sur les 30 derniers jours
    @users_this_month = User.where(created_at: 1.month.ago..).count

    # Répartition par genre (ex: { "femme" => 12, "homme" => 8, "autre" => 2 })
    @users_by_genre = User.group(:genre).count

    # ── KPIs Matchs ──────────────────────────────────────────────────────────
    # Nombre total de matchs créés depuis le début
    @total_matches = Match.count

    # Répartition par sport (ex: { "Football" => 10, "Basketball" => 5 })
    # joins(:sport) exclut les matchs sans sport assigné
    @matches_by_sport = Match.joins(:sport).group("sports.name").count

    # Matchs terminés — utilise le scope .completed défini dans le modèle Match
    @completed_matches = Match.completed.count

    # Matchs à venir — utilise le scope .upcoming défini dans le modèle Match
    @upcoming_matches = Match.upcoming.count

    # ── KPIs Avis ────────────────────────────────────────────────────────────
    # Nombre total d'avis laissés sur la plateforme
    @total_avis = Avis.count

    # Note moyenne globale sur tous les avis (arrondie à 2 décimales)
    # &.round(2) évite une erreur si aucun avis n'existe encore (retourne nil)
    @average_rating = Avis.average(:rating)&.round(2)

    # ── Top Joueurs ──────────────────────────────────────────────────────────
    # Les 5 joueurs avec la meilleure note moyenne
    # includes(:user) évite les N+1 queries (charge les users en une seule requête)
    @top_players = Profil.where.not(average_rating: nil)
                         .order(average_rating: :desc)
                         .limit(5)
                         .includes(:user)

    # ── Derniers inscrits ────────────────────────────────────────────────────
    # Les 10 derniers utilisateurs inscrits
    # includes(:profil) évite les N+1 queries pour afficher leur prénom/nom
    @recent_users = User.order(created_at: :desc)
                        .limit(10)
                        .includes(:profil)
  end
end
