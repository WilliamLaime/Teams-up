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
# Robustesse : chaque appel API est isolé (une erreur sur users.list ne doit pas faire
# disparaître les channels, et inversement) et on distingue les erreurs FATALES
# d'authentification (token révoqué/invalide → réinstallation requise) des erreurs
# partielles (un scope manquant). Le rendu du formulaire ne plante jamais.
module Slack
  class ChannelLister
    CONVERSATIONS_LIST_URL = "#{Slack::API_BASE_URL}/conversations.list".freeze
    USERS_LIST_URL         = "#{Slack::API_BASE_URL}/users.list".freeze

    # Erreurs Slack signifiant que le jeton du bot est mort : seule une RÉINSTALLATION
    # de l'app (nouveau bot_token) répare, pas une simple nouvelle liaison d'identité.
    FATAL_AUTH_ERRORS = %w[invalid_auth token_revoked account_inactive not_authed].freeze

    # Version riche : hash groupé des destinations + drapeau `auth_failed` indiquant que
    # le workspace doit être réinstallé (token mort ou bot_token illisible).
    #   { groups: { "Channels" => [...], "Messages directs" => [...] }, auth_failed: false }
    def self.resolve(workspace)
      token = read_token(workspace)
      return { groups: {}, auth_failed: false }         if token == :missing
      return { groups: {}, auth_failed: true }          if token == :unreadable

      channels, ch_fatal = safe_fetch { fetch_channels(workspace) }
      members,  mb_fatal = safe_fetch { fetch_members(workspace) }

      groups = {}
      groups["Channels"]         = channels if channels.any?
      groups["Messages directs"] = members  if members.any?

      { groups: groups, auth_failed: ch_fatal || mb_fatal }
    end

    # Compat : renvoie directement le hash groupé (formulaire de partage + JS Stimulus).
    def self.destinations(workspace)
      resolve(workspace)[:groups]
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

    # Lit le bot_token en gérant le cas où il n'existe pas (:missing) et celui où il
    # existe mais n'est plus déchiffrable — clés Active Record Encryption changées —
    # auquel cas la réinstallation est nécessaire (:unreadable).
    def self.read_token(workspace)
      return :missing unless workspace

      token = workspace.bot_token
      token.present? ? token : :missing
    rescue StandardError => e
      Rails.logger.warn("[Slack::ChannelLister] bot_token illisible: #{e.class}")
      :unreadable
    end

    # Exécute un appel API isolé. Renvoie [valeurs, fatal?] : en cas d'erreur, une liste
    # vide et un booléen indiquant si l'erreur est une panne d'authentification fatale.
    def self.safe_fetch
      [yield, false]
    rescue Slack::ApiClient::Error => e
      Rails.logger.warn("[Slack::ChannelLister] #{e.slack_error}")
      [[], FATAL_AUTH_ERRORS.include?(e.slack_error)]
    rescue StandardError => e
      Rails.logger.warn("[Slack::ChannelLister] #{e.class}: #{e.message}")
      [[], false]
    end

    private_class_method :fetch_channels, :fetch_members, :read_token, :safe_fetch
  end
end
