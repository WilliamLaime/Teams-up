class MatchUserPolicy < ApplicationPolicy
  # Tout utilisateur connecté peut rejoindre un match
  def create?
    true
  end

  # Un joueur peut seulement quitter sa propre inscription
  def destroy?
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

  private

  # Vérifie si l'utilisateur connecté est l'organisateur du match
  def organizer?
    record.match.match_users.exists?(user: user, role: "organisateur")
  end
end
