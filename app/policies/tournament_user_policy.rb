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

  # Déclarer le forfait d'un joueur : réservé à l'organisateur (admin ou co-org).
  def withdraw?
    user.present? && record.tournament.organizer?(user)
  end
end
