class Notification < ApplicationRecord
  belongs_to :user

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
    # Met à jour le CONTENU du turbo_frame "notification_bell" dans la navbar.
    # On utilise broadcast_update_to (et non broadcast_replace_to) pour conserver
    # l'élément <turbo-frame id="notification_bell"> dans le DOM.
    # Avec broadcast_replace_to, le frame entier était remplacé par le contenu du partial
    # (qui n'a pas de turbo_frame wrapper), ce qui faisait disparaître l'id "notification_bell"
    # du DOM → les broadcasts suivants ne trouvaient plus la cible → cloche figée/disparue.
    broadcast_update_to(
      [user, :notifications],          # canal unique pour cet utilisateur
      target: "notification_bell",     # id du turbo_frame dans la navbar
      partial: "shared/notification_bell",
      locals: { current_user: user }   # on passe l'utilisateur au partial
    )
  end
end
