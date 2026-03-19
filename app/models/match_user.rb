class MatchUser < ApplicationRecord
  belongs_to :user
  belongs_to :match

  # Statuts possibles pour une inscription
  # "waiting" = en file d'attente (match complet)
  STATUSES = ["pending", "approved", "rejected", "waiting"].freeze

  # ── Callbacks Turbo Stream pour le sticky chat ──────────────────────────────
  # Quand un utilisateur est créé en tant qu'organisateur → ajoute la conv en temps réel
  after_create_commit :broadcast_new_convo_to_sidebar,
    if: -> { role == "organisateur" }

  # Quand un joueur passe à "approved" → ajoute la conv en temps réel dans sa sidebar
  after_update_commit :broadcast_new_convo_to_sidebar,
    if: -> { saved_change_to_status? && status == "approved" }

  # Helpers pour vérifier le statut facilement
  def approved?
    status == "approved"
  end

  def pending?
    status == "pending"
  end

  def rejected?
    status == "rejected"
  end

  # Retourne vrai si le joueur est en file d'attente (match complet)
  def waiting?
    status == "waiting"
  end

  private

  # Ajoute la nouvelle conversation en haut de la sidebar sticky chat de l'utilisateur.
  # Déclenché quand il devient organisateur ou joueur approuvé.
  # Supprime aussi le message "Rejoins un match !" s'il était affiché.
  def broadcast_new_convo_to_sidebar
    # On n'ajoute pas les matchs déjà terminés dans la sidebar
    return if match.past?

    stream = "user_conversations_#{user_id}"

    # Prépend l'item de conversation en haut de la liste (apparaît immédiatement)
    broadcast_prepend_to(
      stream,
      target: "sticky-chat-sidebar-list",
      partial: "shared/sticky_convo_item",
      locals: { match: match, match_user: self }
    )

    # Supprime le message vide "Rejoins un match !" s'il est encore affiché
    broadcast_remove_to(stream, target: "sticky-chat-sidebar-empty")

    # Pour l'organisateur (création de match) : ouvre le panneau et charge la conv automatiquement
    if role == "organisateur"
      # Récupère le chemin vers la conversation du match
      convo_path = Rails.application.routes.url_helpers.conversation_path(match)

      # Remplace le turbo-frame par un nouveau avec src= pour que Turbo charge la conv
      broadcast_replace_to(
        stream,
        target: "sticky-chat-frame",
        html: "<turbo-frame id=\"sticky-chat-frame\" src=\"#{convo_path}\" loading=\"eager\"></turbo-frame>"
      )

      # Met à jour le trigger caché — détecté par le MutationObserver Stimulus
      # qui appellera open() pour ouvrir le panneau
      broadcast_update_to(
        stream,
        target: "sticky-chat-open-trigger",
        html: match.id.to_s
      )
    end
  end
end
