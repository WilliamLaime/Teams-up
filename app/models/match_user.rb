class MatchUser < ApplicationRecord
  belongs_to :user
  belongs_to :match

  # Statuts possibles pour une inscription
  # "waiting" = en file d'attente (match complet)
  STATUSES = ["pending", "approved", "rejected", "waiting"].freeze

  # ── Callbacks Turbo Stream pour le sticky chat ──────────────────────────────
  # Quand un utilisateur rejoint un match (organisateur OU joueur auto-approuvé) → ajoute la conv en temps réel
  after_create_commit :broadcast_new_convo_to_sidebar,
                      if: -> { role == "organisateur" || status == "approved" }

  # Quand un joueur passe à "approved" → ajoute la conv en temps réel dans sa sidebar
  after_update_commit :broadcast_new_convo_to_sidebar,
                      if: -> { saved_change_to_status? && status == "approved" }

  # ── Source de vérité des places restantes ───────────────────────────────────
  # Toute variation du nombre de joueurs confirmés recalcule match.player_left.
  # Centraliser ici couvre TOUS les chemins (join auto, validation manuelle,
  # confirm d'un membre d'équipe, reject, départ, promotion depuis la file)
  # sans dépendre de decrement!/increment! manuels disséminés dans le controller.
  # after_save (pas _commit) : le recalcul reste dans la transaction, donc sous
  # le même verrou (with_lock) que les inscriptions concurrentes.
  after_save :recompute_match_places, if: :saved_change_to_status?
  after_destroy :recompute_match_places

  # ── Diffusion temps réel du bloc "places" ───────────────────────────────────
  # Après COMMIT (données garanties en base) on pousse le bloc places à jour à
  # tous les visiteurs de la page match. Couvre TOUS les chemins :
  #   - create  : join auto (approved) ou file d'attente (waiting)
  #   - update  : acceptation manuelle, refus, promotion depuis la file (status)
  #   - destroy : départ d'un joueur
  # after_commit (pas after_save) : évite d'émettre pendant la transaction/verrou.
  #
  # ⚠️ PIÈGE ActiveSupport : enregistrer le MÊME symbole de méthode pour
  # after_create_commit + after_update_commit + after_destroy_commit fait
  # que les callbacks se DÉDUPLIQUENT en une seule entrée aux conditions
  # (`on:`) conflictuelles → le callback ne se déclenche JAMAIS.
  # Solution : un unique `after_commit` couvre create + update + destroy en
  # une seule inscription, sans collision. Re-diffuser un bloc identique est
  # idempotent (Turbo remplace la même cible), donc sans effet de bord.
  after_commit :broadcast_match_spots

  # ── Rafraîchissement des cartes Slack ───────────────────────────────────────
  # La carte Slack d'un match affiche la liste des inscrits (voir
  # Slack::BlockKitBuilder#enrolled_players_label). Toute inscription qui ENTRE
  # ou SORT de cette liste (approbation, refus, départ) doit ré-éditer les cartes
  # suivies pour rester à jour — que l'inscription vienne du web ou de Slack.
  # SlackMatchStatusJob reconstruit la carte ENTIÈRE (statut + détails + inscrits)
  # et est idempotent : on le réutilise ici comme rafraîchisseur générique.
  after_commit :refresh_slack_cards

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

  # Retourne vrai si le joueur a confirmé son paiement
  def paid?
    payment_confirmed?
  end

  private

  # Resynchronise les places restantes du match parent.
  # (association déjà chargée dans la plupart des chemins ; sinon un simple find)
  def recompute_match_places
    match.recompute_player_left!
  end

  # Pousse le bloc "places" à jour à tous les visiteurs de la page match.
  # Garde : si le match parent est en cours de suppression (dependent: :destroy),
  # on ne diffuse pas (le match n'existe plus).
  def broadcast_match_spots
    return if destroyed_by_association

    match.broadcast_spots
  end

  # Ajoute la nouvelle conversation en haut de la sidebar sticky chat de l'utilisateur.
  # Déclenché quand il devient organisateur ou joueur approuvé.
  # Supprime aussi le message "Rejoins un match !" s'il était affiché.
  # Ré-édite les cartes Slack du match quand la liste des inscrits a pu changer.
  # On n'enfile le job que si :
  #   - le match n'est pas en cours de suppression (sinon plus de cartes) ;
  #   - la liste "approuvés + organisateur" a réellement bougé (départ, ou
  #     franchissement de la limite "approved") — un pending créé/refusé
  #     n'apparaît pas sur la carte Slack, donc pas de rafraîchissement inutile ;
  #   - le match possède au moins une carte Slack suivie (évite un job à vide).
  def refresh_slack_cards
    return if destroyed_by_association
    return unless slack_list_changed?
    return unless match.slack_match_messages.exists?

    SlackMatchStatusJob.perform_later(match_id)
  end

  # Statuts qui apparaissent sur la carte Slack (groupes "Inscrits" + "En attente").
  # rejected/waiting n'y figurent pas → un passage vers/depuis ces statuts ne
  # concerne la carte que s'il quitte/rejoint l'un des statuts listés.
  SLACK_LISTED_STATUSES = %w[pending approved].freeze

  # Vrai si l'ensemble affiché sur la carte Slack a pu changer lors de cette
  # opération : départ d'un joueur (destroy), ou changement de statut dont
  # l'ancien OU le nouveau figure parmi les statuts listés sur la carte.
  def slack_list_changed?
    return true if destroyed?
    return false unless saved_change_to_status?

    SLACK_LISTED_STATUSES.include?(status) ||
      SLACK_LISTED_STATUSES.include?(status_before_last_save)
  end

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
    return unless role == "organisateur"

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
