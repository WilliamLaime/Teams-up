# ── Service MatchCancellationService ──────────────────────────────────────────
# Encapsule l'annulation d'un match (= suppression, comme l'existant), extraite
# de MatchesController#destroy pour être réutilisable depuis Slack (bouton
# « Annuler le match »). Symétrique des autres services métier.
#
# Ordre CRITIQUE : tout ce qui a besoin du match ou de ses cartes Slack doit être
# capturé AVANT le destroy, car `dependent: :destroy` supprime en cascade les
# slack_match_messages, et SolidQueue ne peut pas recharger un enregistrement
# détruit (d'où la sérialisation en scalaires pour les emails).
#
# Étapes :
#   1. capture des destinataires + données email (scalaires) + coordonnées des
#      cartes Slack suivies ;
#   2. notification temps réel des participants (canal ActionCable encore vivant) ;
#   3. destroy du match ;
#   4. emails d'annulation asynchrones + édition des cartes Slack en « Annulé ».
class MatchCancellationService
  Result = Struct.new(:status, :title, keyword_init: true)

  def initialize(match:)
    @match = match
  end

  def call
    participants = @match.match_users
                         .where.not(role: "organisateur")
                         .where(status: %w[approved pending waiting])
                         .includes(:user)

    recipient_emails = participants.map { |mu| mu.user.email }
    recipient_emails << @match.user.email

    email_args  = capture_email_args
    slack_cards = capture_slack_cards
    title       = @match.title

    # Broadcasts Turbo AVANT destroy → le canal ActionCable doit encore exister.
    participants.each { |mu| broadcast_cancellation(mu.user) }

    @match.destroy

    recipient_emails.each { |email| MatchCancelledMailerJob.perform_later(email, *email_args) }
    SlackMatchCancelJob.perform_later(title, slack_cards) if slack_cards.any?

    Result.new(status: :cancelled, title: title)
  end

  private

  # Scalaires pour l'email (aucun objet AR : le match sera détruit).
  # Ordre calqué sur MatchCancelledMailerJob#perform.
  def capture_email_args
    [
      @match.title,
      @match.date,
      @match.time&.strftime("%Hh%M"),
      @match.venue&.name,
      @match.venue&.city,
      @match.user.display_name
    ]
  end

  # Coordonnées des cartes Slack (hashes sérialisables) captées avant la cascade
  # destroy, pour pouvoir les éditer en « Annulé » ensuite.
  def capture_slack_cards
    @match.slack_match_messages.map do |msg|
      { "workspace_id" => msg.slack_workspace_id,
        "channel_id"   => msg.channel_id,
        "message_ts"   => msg.message_ts }
    end
  end

  # Notifie un participant en temps réel (modale « Match annulé »), peu importe
  # la page où il se trouve. Rendu du partial hors controller via Turbo.
  def broadcast_cancellation(participant_user)
    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{participant_user.id}_notifications",
      target:  "global_notification_container",
      partial: "matches/match_cancelled_notification",
      locals:  { match: @match }
    )
  end
end
