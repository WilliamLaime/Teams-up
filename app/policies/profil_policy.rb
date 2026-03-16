class ProfilPolicy < ApplicationPolicy
  # Tout utilisateur peut voir son propre profil
  def show?
    owner?
  end

  # Seul le propriétaire peut modifier son profil
  # edit? appelle automatiquement update? (défini dans ApplicationPolicy)
  def update?
    owner?
  end

  private

  # Vérifie que l'utilisateur connecté est le propriétaire du profil
  def owner?
    record.user == user
  end
end
