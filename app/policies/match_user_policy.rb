class MatchUserPolicy < ApplicationPolicy
  # Tout utilisateur connecté peut rejoindre un match
  def create?
    true
  end

  # Un joueur peut seulement quitter sa propre inscription.
  #
  # Exception : une confrontation de tournoi. Son affiche est décidée par le
  # tableau — si un adversaire pouvait s'en retirer, la rencontre resterait
  # ouverte avec un seul joueur et la carte du tournoi n'aurait plus de sens.
  # Le retrait légitime passe par le forfait déclaré côté tournoi, ou par la
  # suppression de la rencontre par son organisateur.
  def destroy?
    return false if record.match.tournament_confrontation?

    record.user == user
  end

  # Seul l'organisateur du match peut approuver un joueur
  def approve?
    organizer?
  end

  # Seul l'organisateur du match peut rejeter un joueur
  def reject?
    organizer?
  end

  # Seul le membre concerné peut confirmer sa propre place (match d'équipe)
  def confirm?
    record.user == user
  end

  # L'organisateur peut marquer n'importe quel joueur comme payé/non payé
  # Un joueur peut aussi basculer son propre statut de paiement
  def toggle_payment?
    organizer? || record.user == user
  end

  private

  # Vérifie si l'utilisateur connecté est l'organisateur du match
  def organizer?
    record.match.match_users.exists?(user: user, role: "organisateur")
  end
end
