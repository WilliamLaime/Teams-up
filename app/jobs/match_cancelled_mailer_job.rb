# Envoie l'email d'annulation de match de façon asynchrone.
# Accepte uniquement des données scalaires pour éviter le DeserializationError
# de SolidQueue qui tente de recharger un AR object supprimé via GlobalID.
#
# Sécurité retry : les arguments sont 100 % scalaires (String, Date) → pas de
# GlobalID → pas de DeserializationError si SolidQueue rejoue le job après un
# échec réseau/SMTP. Le retry est donc sûr.
class MatchCancelledMailerJob < ApplicationJob
  queue_as :default

  # Retry sur erreurs réseau/SMTP (SendGrid down, timeout…)
  retry_on Net::SMTPAuthenticationError,
           Net::SMTPServerBusy,
           Net::SMTPFatalError,
           Net::SMTPUnknownError,
           Errno::ECONNRESET,
           wait: :polynomially_longer,
           attempts: 5

  # @param user_email     [String]      email du destinataire
  # @param match_title    [String]      titre du match annulé
  # @param match_date     [Date]        date du match (sérialisée nativement par ActiveJob)
  # @param match_time_str [String, nil] heure formatée "HHhMM" ou nil
  # @param venue_name     [String, nil] nom du lieu ou nil
  # @param venue_city     [String, nil] ville du lieu ou nil
  # @param organizer_name [String]      display_name de l'organisateur
  def perform(user_email, match_title, match_date, match_time_str, venue_name, venue_city, organizer_name)
    UserMailer.match_cancelled_async(
      user_email:,
      match_title:,
      match_date:,
      match_time_str:,
      venue_name:,
      venue_city:,
      organizer_name:
    ).deliver_now
  end
end
