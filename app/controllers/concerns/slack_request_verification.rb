# Vérifie l'authenticité des requêtes ENTRANTES de Slack (interactivity, slash
# commands, events). C'est LA protection de ces endpoints : ils sont publics (pas
# de session, pas de CSRF token), donc on s'assure que la requête vient bien de
# Slack via la signature HMAC signée avec le Signing Secret de l'app.
#
# Algorithme officiel Slack :
#   base      = "v0:{timestamp}:{corps brut exact de la requête}"
#   signature = "v0=" + HMAC_SHA256(signing_secret, base)  (en hexadécimal)
# puis comparaison en temps constant avec l'en-tête X-Slack-Signature.
#
# Deux pièges couverts :
#   - le corps doit être le RAW body exact (request.raw_post), pas les params reparsés ;
#   - anti-replay : on rejette au-delà de 5 min d'écart (une signature interceptée
#     ne peut pas être rejouée indéfiniment).
module SlackRequestVerification
  extend ActiveSupport::Concern

  # Écart maximal toléré entre l'horodatage de la requête et maintenant (secondes).
  MAX_TIMESTAMP_SKEW = 5 * 60

  private

  def verify_slack_signature!
    secret = Slack.signing_secret
    # Sans secret configuré, on ne PEUT pas vérifier → on refuse (fail-closed).
    return head :unauthorized if secret.blank?

    timestamp = request.headers["X-Slack-Request-Timestamp"].to_s
    signature = request.headers["X-Slack-Signature"].to_s
    return head :unauthorized if timestamp.blank? || signature.blank?

    # Anti-replay : rejette les requêtes trop anciennes ou aux horodatages aberrants.
    return head :unauthorized if (Time.now.to_i - timestamp.to_i).abs > MAX_TIMESTAMP_SKEW

    base     = "v0:#{timestamp}:#{request.raw_post}"
    expected = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", secret, base)

    # Comparaison en temps constant (évite les attaques temporelles).
    return if ActiveSupport::SecurityUtils.secure_compare(expected, signature)

    head :unauthorized
  end
end
