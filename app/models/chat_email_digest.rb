# ── Fenêtre de regroupement des notifications de chat ────────────────────────
# Une ligne par (destinataire, conversation). Elle évite d'envoyer un mail par
# message : quelqu'un qui écrit une phrase en 3 lignes ne doit déclencher qu'UN
# mail. Le cycle de vie est décrit dans ChatMessageNotifier (ouverture de la
# fenêtre) et ChatEmailDigestJob (envoi à la fermeture, 3 min plus tard).
#
# Ce modèle centralise aussi ce qui dépend du TYPE de conversation (match, équipe,
# conversation privée, match de tournoi) : qui la reçoit, où en est la lecture du
# destinataire, et le lien qui l'ouvre directement. Les 4 cas sont regroupés ici
# pour qu'un 5e type de chat n'ait qu'un seul fichier à compléter.
class ChatEmailDigest < ApplicationRecord
  # Durée de la fenêtre : au plus un mail toutes les 3 min par conversation.
  WINDOW = 3.minutes

  # Au-delà, une fenêtre encore « ouverte » est un job perdu : elle peut être
  # rouverte (cf. ChatMessageNotifier#claim_window?).
  STALE_AFTER = 30.minutes

  # Nombre maximum de messages recopiés dans le mail (les suivants sont résumés
  # par « + N autres messages »).
  MAX_MESSAGES_IN_EMAIL = 5

  belongs_to :user
  belongs_to :chattable, polymorphic: true

  # ── Qui reçoit les messages d'une conversation ─────────────────────────────
  # Renvoie les ids de TOUS les participants (l'expéditeur compris — c'est à
  # l'appelant de l'exclure). Les filtres sont les mêmes que les droits d'accès
  # au chat (MessagesController#set_context_and_check_access,
  # TournamentMatchPolicy#chat?) : on ne notifie jamais quelqu'un qui ne pourrait
  # pas lire la conversation.
  def self.participant_ids_for(chattable)
    case chattable
    when PrivateConversation
      [chattable.sender_id, chattable.recipient_id]
    when Match
      chattable.match_users
               .where("status = 'approved' OR role = 'organisateur'")
               .pluck(:user_id)
    when Team
      chattable.team_members.pluck(:user_id)
    when TournamentMatch
      tournament_match_participant_ids(chattable)
    else
      []
    end
  end

  # Joueurs de la confrontation + créateur et co-organisateurs du tournoi.
  # Un bye n'a pas d'adversaire, donc pas de chat (cf. TournamentMatchPolicy#chat?).
  def self.tournament_match_participant_ids(tournament_match)
    return [] if tournament_match.is_bye

    tournament = tournament_match.tournament
    ids = tournament_match.players.map(&:user_id)
    ids << tournament.user_id
    ids.concat(tournament.tournament_users.where(co_organizer: true).pluck(:user_id))
    ids.compact.uniq
  end

  # La conversation d'un message (le contexte parmi les 4 possibles).
  def self.chattable_for(message)
    message.private_conversation || message.match || message.team || message.tournament_match
  end

  # ── Le destinataire a-t-il toujours accès à la conversation ? ──────────────
  # Revérifié au moment d'envoyer : un joueur retiré du match entre-temps ne
  # doit plus recevoir les messages de son chat.
  def accessible?
    self.class.participant_ids_for(chattable).include?(user_id)
  end

  # ── Dernière lecture de la conversation par le destinataire ────────────────
  # nil = n'a jamais ouvert la conversation. Chaque type stocke cette date à un
  # endroit différent.
  def last_read_at
    case chattable
    when PrivateConversation
      chattable.last_read_at_for(user)
    when Match
      chattable.match_users.find_by(user_id: user_id)&.last_read_at
    when Team
      chattable.team_members.find_by(user_id: user_id)&.chat_last_read_at
    when TournamentMatch
      TournamentMatchChatRead.find_by(tournament_match: chattable, user_id: user_id)&.last_read_at
    end
  end

  # ── Messages à notifier ─────────────────────────────────────────────────────
  # Les messages des AUTRES participants, arrivés après la dernière notification
  # et que le destinataire n'a pas encore lus dans l'application.
  # `up_to` borne la sélection : le job fige cet instant pour que le message
  # arrivé pendant l'envoi ne soit ni perdu ni envoyé deux fois.
  def unread_messages(up_to: Time.current)
    since = [last_sent_at, last_read_at].compact.max

    scope = chattable.messages.where.not(user_id: user_id).where(messages: { created_at: ..up_to })
    scope = scope.where("messages.created_at > ?", since) if since
    scope.order(:created_at)
  end

  # ── Lien qui ouvre directement la conversation ─────────────────────────────
  # Path relatif, stocké tel quel dans Notification#link ; le mail le préfixe
  # de son propre hôte (ChatMailer). Chaque page ouvre la bonne modale grâce au
  # paramètre (cf. modal_autoopen_controller.js et tmatch_chat_controller.js).
  def chat_path
    helpers = Rails.application.routes.url_helpers

    case chattable
    when PrivateConversation
      helpers.user_profil_path(chattable.other_user(user), open_chat: chattable.id)
    when Match
      helpers.match_path(chattable, open_chat: 1)
    when Team
      helpers.team_path(chattable, open_chat: 1)
    when TournamentMatch
      helpers.tournament_path(chattable.tournament, tmatch_chat: chattable.id)
    end
  end

  # ── Libellé de la conversation (objet du mail, notification) ──────────────
  # nil pour une conversation privée : on y nomme la personne, pas un groupe.
  def chat_title
    case chattable
    when Match           then chattable.title
    when Team            then chattable.name
    when TournamentMatch then chattable.tournament.name
    end
  end

  def private_chat?
    chattable.is_a?(PrivateConversation)
  end
end
