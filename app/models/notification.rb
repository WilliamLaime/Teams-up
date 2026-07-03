class Notification < ApplicationRecord
  belongs_to :user

  # actor : l'utilisateur à l'origine de la notification (optionnel)
  # Ex: pour "friend_request", c'est celui qui a envoyé la demande
  belongs_to :actor, class_name: "User", optional: true

  # Scope pour récupérer uniquement les notifications non lues
  scope :unread, -> { where(read: false) }

  # Scope pour trier du plus récent au plus ancien
  scope :recent, -> { order(created_at: :desc) }

  # ── ActionCable : mise à jour en temps réel de la cloche ──────────────────
  # Quand une notification est créée, on remplace la cloche dans la navbar
  # de l'utilisateur concerné — sans qu'il ait besoin de recharger la page.
  #
  # Canal personnalisé par utilisateur : "notifications_user_42" (ex pour user id=42)
  # La navbar s'abonne avec : <%= turbo_stream_from current_user, :notifications %>
  after_create_commit :broadcast_notification_bell

  private

  def broadcast_notification_bell
    # ⚠️  IMPORTANT — Pourquoi on NE passe PAS partial: ici
    # ────────────────────────────────────────────────────────
    # En production, stack : Solid Queue (jobs) + Solid Cable (WebSocket).
    # Quand broadcast_update_to reçoit partial: "...", Turbo Rails enfile
    # un Turbo::Streams::BroadcastJob dans Solid Queue pour rendre le partial.
    # Ce job doit être traité par un worker AVANT que le message parte vers
    # Solid Cable. Si le worker a un délai ou un incident, le broadcast est
    # silencieusement perdu → la pastille n'apparaît pas en temps réel.
    #
    # Solution : rendre le partial synchronement ici (dans le thread de la
    # requête, juste après le commit) et passer html: au lieu de partial:.
    # broadcast_update_to avec html: appelle directement ActionCable.server.broadcast
    # → Solid Cable → client en ~100 ms, SANS passer par Solid Queue.
    html = ApplicationController.render(
      partial: "shared/notification_bell",
      locals: { current_user: user }
    )

    # On utilise broadcast_update_to (et non broadcast_replace_to) pour conserver
    # l'élément <turbo-frame id="notification_bell"> dans le DOM.
    # broadcast_replace_to remplacerait le frame lui-même → son id disparaît
    # → les broadcasts suivants ne trouvent plus la cible → cloche figée.
    broadcast_update_to(
      [user, :notifications], # canal unique par utilisateur
      target: "notification_bell",
      html: html
    )
  rescue StandardError => e
    # Filet de sécurité : si le rendu ou le broadcast échoue, on logue sans
    # propager l'exception — la notification est déjà sauvegardée en base.
    Rails.logger.error("[Notification] Broadcast cloche échoué (user #{user_id}) : #{e.class} — #{e.message}")
  end
end
