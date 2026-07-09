# Autorisations sur les inscriptions à un tournoi (Pundit).
class TournamentUserPolicy < ApplicationPolicy
  # Tout utilisateur connecté peut s'inscrire à un tournoi.
  def create?
    user.present?
  end

  # On ne peut retirer que sa propre inscription.
  def destroy?
    record.user == user
  end
end
