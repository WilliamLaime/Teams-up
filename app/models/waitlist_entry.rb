# Stocke les emails des visiteurs souhaitant être notifiés au lancement.
# Un email par entrée, unicité garantie en base ET en validation Rails.
class WaitlistEntry < ApplicationRecord
  # Normalise l'email en minuscules avant validation et sauvegarde
  before_validation { self.email = email.to_s.strip.downcase }

  validates :email,
            presence:   true,
            uniqueness: { case_sensitive: false, message: :taken },
            format:     { with: URI::MailTo::EMAIL_REGEXP, message: :invalid }
end
