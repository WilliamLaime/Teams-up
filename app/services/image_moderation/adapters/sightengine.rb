# Adapter Sightengine pour la détection NSFW via le modèle `nudity-2.1`.
#
# Appelle l'endpoint public `api.sightengine.com/1.0/check.json` en POST
# multipart, parse la réponse JSON et construit un `ImageModeration::Result`.
#
# Choix de net/http plutôt que httparty/faraday : le projet n'a aucune gem
# HTTP cliente installée et un seul appel POST multipart ne justifie pas d'en
# ajouter une. net/http + Net::HTTP::Post::Multipart (fournies par la stdlib
# via le module `net/http`) suffisent largement.
#
# Règle de score appliquée : on prend le max des 4 catégories VRAIMENT
# explicites et on ignore toute la famille `suggestive_classes` qui contient
# bikini, male_chest, swimwear, etc. — ces catégories sont légitimes dans un
# contexte sportif (photos de beach volley, natation, torse nu à l'entraînement)
# et ne doivent PAS déclencher de rejet.
#
# Les 4 catégories évaluées :
#   - sexual_activity : acte sexuel
#   - sexual_display  : exhibition de parties génitales
#   - erotica         : pose érotique explicite
#   - very_suggestive : très fortement sexualisé
#
# Exemple de réponse Sightengine attendue :
#   {
#     "status": "success",
#     "nudity": {
#       "sexual_activity": 0.001,
#       "sexual_display":  0.001,
#       "erotica":         0.001,
#       "very_suggestive": 0.001,
#       ...
#     }
#   }
class ImageModeration
  module Adapters
    class Sightengine < Base
      # URL de l'API Sightengine (endpoint stable, existe depuis des années)
      ENDPOINT = URI("https://api.sightengine.com/1.0/check.json").freeze

      # Modèle à appeler côté Sightengine. `nudity-2.1` est la version la plus
      # récente pour la détection de nudité (plus précise que nudity-2.0 et
      # surtout que la v1 dépréciée).
      MODELS = "nudity-2.1".freeze

      # Timeouts réseau conservateurs. On ne veut pas qu'un job traîne des
      # minutes si Sightengine est lent ou en panne : mieux vaut échouer vite
      # et laisser le retry du Job reprendre plus tard.
      OPEN_TIMEOUT = 5   # secondes pour établir la connexion TCP
      READ_TIMEOUT = 15  # secondes pour recevoir la réponse complète

      # Les 4 seules clés de `nudity` qu'on prend en compte pour le score.
      # Voir commentaire en tête de fichier pour la justification.
      EVALUATED_KEYS = %w[sexual_activity sexual_display erotica very_suggestive].freeze

      # @param api_user   [String] identifiant public Sightengine
      # @param api_secret [String] clé secrète Sightengine
      #
      # Par défaut, on lit les variables d'environnement directement. Les tests
      # peuvent injecter des fake credentials sans toucher à l'environnement.
      def initialize(api_user: ENV.fetch("SIGHTENGINE_API_USER", nil),
                     api_secret: ENV.fetch("SIGHTENGINE_API_SECRET", nil))
        super()
        @api_user   = api_user
        @api_secret = api_secret
      end

      # Analyse une image et retourne un Result.
      #
      # @param io       [IO]     flux binaire de l'image
      # @param filename [String] nom de fichier original (ex: "avatar.jpg")
      # @return [ImageModeration::Result]
      # @raise  [ImageModeration::RateLimitError]   HTTP 429
      # @raise  [ImageModeration::QuotaExceededError] quota mensuel dépassé
      # @raise  [ImageModeration::ApiError]         autres erreurs
      def analyze(io, filename:)
        response = post_multipart(io, filename)
        handle_response(response)
      rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
        # Erreurs réseau bas niveau : on les remonte comme ApiError pour que
        # le Job les retry avec backoff. On garde le message original dans la
        # cause pour faciliter le debug dans les logs.
        raise ImageModeration::ApiError, "Network error: #{e.class.name}: #{e.message}"
      end

      # Identifiant du provider stocké dans la colonne `provider`
      def provider_name
        "sightengine"
      end

      private

      # Construit et envoie la requête POST multipart avec net/http.
      #
      # Sightengine attend :
      #   - un champ `media` contenant le binaire de l'image
      #   - un champ `models` avec la liste de modèles (ici "nudity-2.1")
      #   - les champs `api_user` et `api_secret` pour l'authentification
      #
      # On construit le corps multipart à la main pour ne pas dépendre d'une
      # gem. C'est ~40 lignes mais très stable et testable.
      def post_multipart(io, filename)
        boundary = "----ImageModerationBoundary#{SecureRandom.hex(10)}"
        body     = build_multipart_body(io, filename, boundary)

        http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
        http.use_ssl      = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Post.new(ENDPOINT.request_uri)
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        http.request(request)
      end

      # Assemble le corps multipart manuellement.
      # Format standard d'un POST multipart : chaque champ est séparé par
      # "--<boundary>", le dernier par "--<boundary>--".
      # Les lignes utilisent CRLF ("\r\n") comme exige la RFC 7578.
      def build_multipart_body(io, filename, boundary)
        eol = "\r\n"
        parts = []

        # Champs texte : api_user, api_secret, models
        { "api_user" => @api_user, "api_secret" => @api_secret, "models" => MODELS }.each do |name, value|
          parts << "--#{boundary}"
          parts << %(Content-Disposition: form-data; name="#{name}")
          parts << ""
          parts << value.to_s
        end

        # Champ fichier : media
        parts << "--#{boundary}"
        parts << %(Content-Disposition: form-data; name="media"; filename="#{filename}")
        parts << "Content-Type: application/octet-stream"
        parts << ""
        parts << io.read.force_encoding("BINARY")

        # Terminateur multipart
        parts << "--#{boundary}--"
        parts << ""

        parts.join(eol)
      end

      # Dispatche sur le code HTTP et le contenu de la réponse pour lever la
      # bonne exception ou construire un Result.
      def handle_response(response)
        case response.code.to_i
        when 200
          parse_success(response.body)
        when 429
          raise ImageModeration::RateLimitError, "Sightengine rate limit: #{response.body}"
        when 400..499
          # Erreurs 4xx : on regarde le contenu pour distinguer quota dépassé
          # des erreurs de credentials / requête mal formée.
          parse_client_error(response)
        else
          raise ImageModeration::ApiError, "Sightengine #{response.code}: #{response.body}"
        end
      end

      # Parse une réponse 200 OK et construit un Result.
      # Format attendu : { "status": "success", "nudity": { ... } }
      # Si le JSON est invalide ou ne contient pas `nudity`, on lève ApiError
      # pour déclencher un retry (ça peut arriver ponctuellement sur un
      # serveur qui bégaye).
      def parse_success(body)
        json = JSON.parse(body)

        unless json["status"] == "success" && json["nudity"].is_a?(Hash)
          raise ImageModeration::ApiError, "Unexpected Sightengine payload: #{body}"
        end

        nudity = json["nudity"]
        score  = EVALUATED_KEYS.map { |k| nudity[k].to_f }.max || 0.0

        ImageModeration::Result.new(score: score, raw: json)
      rescue JSON::ParserError => e
        raise ImageModeration::ApiError, "Invalid JSON from Sightengine: #{e.message}"
      end

      # Parse une erreur 4xx. Sightengine met les détails dans le JSON de la
      # réponse avec un champ `error.type`. Les valeurs qu'on distingue :
      #   - "usage_limit" → quota mensuel dépassé (QuotaExceededError, pas de retry)
      #   - autres      → ApiError (retry)
      def parse_client_error(response)
        json = begin
          JSON.parse(response.body)
        rescue StandardError
          {}
        end
        error_type = json.dig("error", "type").to_s

        case error_type
        when "usage_limit", "monthly_limit"
          raise ImageModeration::QuotaExceededError, "Sightengine quota exceeded: #{response.body}"
        else
          raise ImageModeration::ApiError, "Sightengine #{response.code}: #{response.body}"
        end
      end
    end
  end
end
