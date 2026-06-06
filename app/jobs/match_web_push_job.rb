# Envoie des notifications Web Push aux utilisateurs dont le profil correspond
# au match qui vient d'être créé (sport + niveau + localisation).
# Déclenché depuis MatchesController#create via perform_later.
class MatchWebPushJob < ApplicationJob
  queue_as :default

  # Une subscription expirée (navigateur réinitialisé, etc.) → on la supprime proprement
  retry_on WebPush::ExpiredSubscription, attempts: 1 do |job, _error|
    PushSubscription.find_by(endpoint: job.arguments.first)&.destroy
  end

  # Erreur réseau ou serveur push → on réessaie avec backoff exponentiel
  retry_on WebPush::Error, wait: :polynomially_longer, attempts: 3

  # Le match a été supprimé entre la planification et l'exécution → on abandonne
  discard_on ActiveRecord::RecordNotFound

  def perform(match_id)
    match = Match.find(match_id)

    # On n'envoie des notifications que pour les matchs publics avec des places disponibles
    return unless match.visibility == "public"
    return unless match.player_left.nil? || match.player_left.positive?

    candidates = find_candidates(match)
    return if candidates.empty?

    candidates.find_each do |user|
      user.push_subscriptions.each do |subscription|
        send_push(subscription, match)
      end
    end
  end

  private

  # Trouve les utilisateurs intéressés par ce match selon 3 critères :
  # 1. Pratiquent ce sport
  # 2. Ont le bon niveau pour ce sport
  # 3. Ont la ville ou le lieu dans leurs préférences
  def find_candidates(match)
    return User.none unless match.sport_id.present?

    # Base : users qui pratiquent ce sport
    candidates = User.joins(profil: :sport_profils)
                     .where(sport_profils: { sport_id: match.sport_id })

    # Filtre par niveau si le match a un niveau spécifique
    if match.level.present? && match.level != "Tout niveau"
      candidates = candidates.where(sport_profils: { level: [match.level, "Tout niveau"] })
    end

    # Filtre par localisation : lieu favori en priorité, sinon ville préférée
    candidates = if match.venue_id.present?
                   candidates.joins(profil: :profil_favorite_venues)
                             .where(profil_favorite_venues: { venue_id: match.venue_id })
                 elsif match.place.present?
                   candidates.joins(:profil)
                             .where("profils.preferred_city ILIKE ?", "%#{match.place}%")
                 else
                   User.none # Pas de localisation → on n'envoie pas de push (risque de spam)
                 end

    # Exclure le créateur du match (inutile de se notifier soi-même)
    candidates.where.not(id: match.user_id).distinct
  end

  # Envoie une notification push à une subscription donnée via la gem web-push
  def send_push(subscription, match)
    sport_name = match.sport&.name || "Sport"
    city       = match.venue&.city || match.place || "votre ville"
    level_text = match.level.present? ? " — Niveau #{match.level}" : ""

    payload = JSON.generate(
      title: "Nouveau match de #{sport_name}",
      body: "Un match à #{city} vous correspond#{level_text}",
      url: Rails.application.routes.url_helpers.match_path(match)
    )

    WebPush.payload_send(
      message: payload,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: {
        subject: "mailto:contact@teams-up-sport.fr",
        public_key: ENV.fetch("VAPID_PUBLIC_KEY"),
        private_key: ENV.fetch("VAPID_PRIVATE_KEY")
      }
    )
  rescue WebPush::ExpiredSubscription
    # Subscription invalide → on la supprime pour ne plus gaspiller de requêtes
    subscription.destroy
  end
end
