module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Identifie l'utilisateur connecté via la session Devise/Warden
    # Si l'utilisateur n'est pas connecté, la connexion est rejetée
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # Récupère l'utilisateur depuis la session (méthode Devise)
      if (verified_user = env["warden"].user)
        verified_user
      else
        reject_unauthorized_connection
      end
    end
  end
end
