# Poste un message dans un channel Slack via l'API Web (chat.postMessage).
#
# S'appuie sur Slack::ApiClient (Net::HTTP + gestion du `ok:false`). Le jeton utilisé
# est le bot_token du workspace (déchiffré à la volée par SlackWorkspace).
class SlackNotifierService
  CHAT_POST_MESSAGE_URL = "#{Slack::API_BASE_URL}/chat.postMessage".freeze

  def initialize(workspace)
    @workspace = workspace
  end

  # Poste un message composé de blocs Block Kit.
  #   channel : ID du channel Slack (ex. "C0123") — obligatoire
  #   blocks  : tableau de blocs Block Kit (rendu riche)
  #   text    : texte de repli (notifications mobiles, accessibilité) — obligatoire
  # Renvoie la réponse Slack parsée. Laisse remonter Slack::ApiClient::Error à l'appelant
  # (le job décide de réessayer ou d'abandonner selon l'erreur).
  def post_message(channel:, text:, blocks:)
    Slack::ApiClient.post_json(
      CHAT_POST_MESSAGE_URL,
      @workspace.bot_token,
      channel: channel,
      text: text,
      blocks: blocks
    )
  end
end
