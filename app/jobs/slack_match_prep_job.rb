# Poste un rappel "préparez-vous" dans le(s) channel(s) Slack d'un match, ~15 min
# avant le coup d'envoi. Planifié comme SlackMatchStatusJob (à build_datetime -
# 15 min), aux deux mêmes points d'ancrage : au partage sur Slack et à chaque
# changement d'horaire.
#
# Anti-doublon (délicat car les replanifications EMPILENT des jobs sans annuler
# les anciens) :
#   1. garde temporelle dans #perform : on n'envoie que si le match est encore à
#      venir ET imminent → un job caduc (ancien horaire) est ignoré ;
#   2. flag `slack_prep_sent_at` claim sous verrou → un seul envoi par créneau,
#      même si deux jobs se déclenchent au même instant (ex. horaire remis à sa
#      valeur initiale). Le flag est remis à nil quand l'horaire change
#      (Match#resync_slack_messages), pour autoriser un nouveau rappel.
class SlackMatchPrepJob < ApplicationJob
  queue_as :default

  # Match supprimé entre l'enqueue et l'exécution → plus rien à faire.
  discard_on ActiveRecord::RecordNotFound

  LEAD_TIME = 15.minutes
  # Retard de queue toléré : au-delà, "dans 15 min" n'a plus de sens, on renonce.
  MAX_LATENESS = 5.minutes

  PERMANENT_SLACK_ERRORS = SlackNotifyJob::PERMANENT_SLACK_ERRORS

  # Planifie le rappel à build_datetime - 15 min (futur uniquement).
  def self.schedule(match)
    start_at = match.build_datetime
    return if start_at.blank?

    at = start_at - LEAD_TIME
    return if at <= Time.current

    set(wait_until: at).perform_later(match.id)
  end

  def perform(match_id)
    match    = Match.find(match_id)
    messages = match.slack_match_messages.includes(:slack_workspace)
    return if messages.empty?

    return unless within_prep_window?(match)
    return unless claim_send(match)

    text = builder.match_prep_text(match)
    messages.each { |msg| post_one(msg, match, text) }
  end

  private

  def builder
    @builder ||= Slack::BlockKitBuilder.new
  end

  # Vrai si le match est encore à venir et démarre dans la fenêtre attendue
  # (~15 min, tolérance de retard de queue). Filtre les jobs devenus caducs
  # après un décalage d'horaire (leur wait_until reste sur l'ancienne heure).
  def within_prep_window?(match)
    start_at = match.build_datetime
    return false if start_at.blank? || start_at <= Time.current

    start_at <= Time.current + LEAD_TIME + MAX_LATENESS
  end

  # Réserve l'envoi de façon atomique : renvoie false si un rappel a déjà été
  # posté pour ce créneau (jobs empilés), true sinon en posant le flag.
  def claim_send(match)
    match.with_lock do
      return false if match.slack_prep_sent_at.present?

      match.update_column(:slack_prep_sent_at, Time.current)
      true
    end
  end

  def post_one(msg, match, text)
    SlackNotifierService.new(msg.slack_workspace).post_message(
      channel: msg.channel_id,
      text: text,
      blocks: builder.match_prep_blocks(match, slack_mentions(match, msg.slack_workspace))
    )
  rescue Slack::ApiClient::Error => e
    # Notif éphémère par nature (utile ~15 min avant) : inutile de retenter plus
    # tard, on log et on passe. Permanente ou transitoire → même traitement.
    Rails.logger.warn("[SlackMatchPrepJob] abandon (#{e.slack_error}) match ##{match.id}")
  end

  # Mentions "<@U…>" des joueurs approuvés (organisateur inclus) ayant lié leur
  # compte Slack dans CE workspace — pour les pinguer nommément. nil si aucun.
  def slack_mentions(match, workspace)
    user_ids = match.match_users.where(status: "approved").pluck(:user_id)
    return nil if user_ids.empty?

    slack_ids = SlackIdentity.where(slack_workspace: workspace, user_id: user_ids)
                             .pluck(:slack_user_id)
    slack_ids.map { |id| "<@#{id}>" }.join(" ").presence
  end
end
