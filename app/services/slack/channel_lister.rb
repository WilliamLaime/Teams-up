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

    # Pagination des endpoints de liste : Slack tronque chaque réponse et fournit un
    # curseur pour la suite (cf. fetch_paginated). 10 pages × 200 = 2000 entrées,
    # largement au-delà des workspaces visés, sans risque de boucle interminable.
    PAGE_SIZE = 200
    MAX_PAGES = 10

    # Durée de vie du cache des destinations (cf. .resolve). Channels et membres d'un
    # workspace bougent rarement, alors que le formulaire de création de match est
    # rendu très souvent : 5 minutes suppriment l'attente sans rendre la liste
    # sensiblement obsolète (un channel créé à l'instant apparaît au pire 5 min plus tard).
    CACHE_TTL = 5.minutes

    # Version riche : hash groupé des destinations + drapeau `auth_failed` indiquant que
    # le workspace doit être réinstallé (token mort ou bot_token illisible).
    #   { groups: { "Channels" => [...], "Messages directs" => [...] }, auth_failed: false }
    #
    # ⚠️ MISE EN CACHE (perf) : sans elle, chaque rendu du formulaire de match ou de
    # tournoi déclenchait DEUX séries d'appels HTTP Slack (conversations.list +
    # users.list, paginés) DANS le cycle de la requête — soit plusieurs centaines de ms
    # à plusieurs secondes avant que la page ne s'affiche, et jusqu'à 8 s par appel si
    # Slack traîne (READ_TIMEOUT). La clé inclut `cache_key_with_version` : une
    # réinstallation du workspace (nouveau bot_token → updated_at modifié) invalide
    # l'entrée d'elle-même, sans attendre le TTL.
    # `force: true` contourne le cache quand l'utilisateur demande explicitement une
    # actualisation de ses destinations.
    def self.resolve(workspace, force: false)
      return uncached_resolve(workspace) if workspace.blank?

      Rails.cache.fetch(["slack/channel_lister", workspace.cache_key_with_version],
                        expires_in: CACHE_TTL, force: force) do
        uncached_resolve(workspace)
      end
    end

    def self.uncached_resolve(workspace)
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
    #
    # ⚠️  Un channel PRIVÉ ne remonte que si le bot en est membre : c'est une règle
    # de l'API Slack, que `groups:read` ne contourne pas. Un channel privé absent
    # de la liste se règle côté Slack, en y invitant l'app.
    def self.fetch_channels(workspace)
      fetch_paginated(CONVERSATIONS_LIST_URL, workspace.bot_token, "channels",
                      types: "public_channel,private_channel",
                      exclude_archived: true)
        .map { |c| ["##{c['name']}", c["id"]] }
        .sort_by { |name, _id| name }
    end

    # Membres humains (hors bots, comptes désactivés et Slackbot) → paires [nom, user_id].
    def self.fetch_members(workspace)
      fetch_paginated(USERS_LIST_URL, workspace.bot_token, "members")
        .reject { |m| m["deleted"] || m["is_bot"] || m["id"] == "USLACKBOT" }
        .map { |m| [m.dig("profile", "real_name").presence || m["name"], m["id"]] }
        .sort_by { |name, _id| name.to_s.downcase }
    end

    # Parcourt toutes les pages d'un endpoint de liste Slack.
    #
    # Slack plafonne chaque réponse (200 éléments ici) et renvoie un curseur dans
    # `response_metadata.next_cursor` tant qu'il reste des données. Sans ce
    # parcours, un workspace de plus de 200 conversations voit les suivantes
    # disparaître du sélecteur — et comme conversations.list ne trie pas par nom,
    # les manquants sont imprévisibles.
    #
    # MAX_PAGES borne le nombre d'appels : ces endpoints sont limités en débit
    # par Slack, et le rendu du formulaire ne doit pas dépendre d'une pagination
    # sans fin.
    def self.fetch_paginated(url, token, key, **params)
      items  = []
      cursor = nil

      MAX_PAGES.times do
        payload = params.merge(limit: PAGE_SIZE)
        payload[:cursor] = cursor if cursor.present?

        # post_form_authed et NON post_json : ces endpoints ignorent un corps
        # JSON sans le signaler (cf. Slack::ApiClient), ce qui renverrait dix
        # fois la première page.
        body = Slack::ApiClient.post_form_authed(url, token, payload)
        items.concat(body[key] || [])

        previous = cursor
        cursor   = body.dig("response_metadata", "next_cursor")
        break if cursor.blank?

        # Garde-fou : un curseur qui ne progresse pas signifie que Slack ne l'a
        # pas pris en compte. Mieux vaut une liste tronquée que la même page
        # répétée MAX_PAGES fois.
        break if cursor == previous
      end

      # Dédoublonnage par id : ceinture et bretelles. Une liste dupliquée est
      # bien plus déroutante pour l'utilisateur qu'une liste incomplète.
      items.uniq { |item| item["id"] }
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

    private_class_method :fetch_channels, :fetch_members, :fetch_paginated, :read_token, :safe_fetch
  end
end
