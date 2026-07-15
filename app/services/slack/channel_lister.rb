# Liste les destinations Slack possibles pour envoyer un match : channels (publics et
# privés) ET membres du workspace (pour un envoi en message direct).
#
# Utilisé par le formulaire de création (choix de la destination) et la page
# Intégrations. Renvoie une structure GROUPÉE prête pour grouped_options_for_select :
#   { "Channels" => [["#general", "C0..."], ...],
#     "Messages directs" => [["Alice Martin", "U0..."], ...] }
#
# À l'envoi, chat.postMessage accepte indifféremment un ID de channel (C.../G...) ou
# un ID d'utilisateur (U...) comme `channel` — dans ce dernier cas Slack ouvre/poste
# le message direct. Aucune distinction n'est donc nécessaire côté envoi.
#
# Robustesse : renvoie {} en cas d'erreur (token révoqué, réseau, scope manquant)
# plutôt que de faire planter le rendu du formulaire.
module Slack
  class ChannelLister
    CONVERSATIONS_LIST_URL = "#{Slack::API_BASE_URL}/conversations.list".freeze
    USERS_LIST_URL         = "#{Slack::API_BASE_URL}/users.list".freeze

    def self.destinations(workspace)
      return {} unless workspace&.bot_token.present?

      groups = {}
      channels = fetch_channels(workspace)
      members  = fetch_members(workspace)
      groups["Channels"] = channels if channels.any?
      groups["Messages directs"] = members if members.any?
      groups
    rescue Slack::ApiClient::Error, StandardError => e
      Rails.logger.warn("[Slack::ChannelLister] #{e.message}")
      {}
    end

    # Channels publics et privés → paires ["#nom", id].
    def self.fetch_channels(workspace)
      body = Slack::ApiClient.post_json(
        CONVERSATIONS_LIST_URL,
        workspace.bot_token,
        types: "public_channel,private_channel",
        exclude_archived: true,
        limit: 200
      )
      (body["channels"] || [])
        .map { |c| ["##{c['name']}", c["id"]] }
        .sort_by { |name, _id| name }
    end

    # Membres humains (hors bots, comptes désactivés et Slackbot) → paires [nom, user_id].
    def self.fetch_members(workspace)
      body = Slack::ApiClient.post_json(USERS_LIST_URL, workspace.bot_token, limit: 200)
      (body["members"] || [])
        .reject { |m| m["deleted"] || m["is_bot"] || m["id"] == "USLACKBOT" }
        .map { |m| [m.dig("profile", "real_name").presence || m["name"], m["id"]] }
        .sort_by { |name, _id| name.to_s.downcase }
    end

    private_class_method :fetch_channels, :fetch_members
  end
end
