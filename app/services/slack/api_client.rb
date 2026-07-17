# Petit client HTTP pour l'API Slack, basé sur Net::HTTP (aucune gem à ajouter).
#
# Deux points d'attention propres à Slack :
#   1. L'API Web répond TOUJOURS en HTTP 200, même en cas d'erreur métier. Le vrai
#      statut est dans le corps JSON : `{ "ok": false, "error": "..." }`. On lève donc
#      une exception dédiée quand `ok` est faux, plutôt que de se fier au code HTTP.
#   2. Les endpoints OAuth attendent des données `application/x-www-form-urlencoded`,
#      tandis que les endpoints de l'API Web (chat.postMessage…) attendent du JSON avec
#      un Bearer token. On expose donc deux méthodes distinctes.
module Slack
  class ApiClient
    # Erreur levée quand Slack renvoie `ok: false`. `error` porte le code Slack brut
    # (ex. "channel_not_found", "not_in_channel", "invalid_auth") pour diagnostic.
    class Error < StandardError
      attr_reader :slack_error

      def initialize(slack_error)
        @slack_error = slack_error
        super("Slack API error: #{slack_error}")
      end
    end

    OPEN_TIMEOUT = 5  # secondes pour établir la connexion
    READ_TIMEOUT = 8  # secondes pour lire la réponse

    # POST form-urlencoded — utilisé pour les échanges OAuth (oauth.v2.access,
    # openid.connect.token). `params` est un Hash de champs de formulaire.
    def self.post_form(url, params)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(params)
      execute(uri, request)
    end

    # POST JSON avec Bearer token — utilisé pour l'API Web (chat.postMessage, views.open…).
    def self.post_json(url, token, payload)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"]  = "application/json; charset=utf-8"
      request.body = payload.to_json
      execute(uri, request)
    end

    # POST JSON vers une `response_url` Slack (fournie dans un payload interactif).
    # Ces URLs sont à usage unique et DÉJÀ authentifiées par un jeton intégré à l'URL :
    # ni Bearer, ni vérification de `ok` (Slack répond par un simple 200). On renvoie
    # la réponse brute Net::HTTP sans la parser.
    def self.post_response_url(url, payload)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json; charset=utf-8"
      request.body = payload.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(request)
    end

    # Exécute la requête, parse le JSON et lève Error si `ok` est faux.
    def self.execute(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      response = http.request(request)
      body = JSON.parse(response.body)

      raise Error, body["error"] unless body["ok"]

      body
    end
    private_class_method :execute
  end
end
