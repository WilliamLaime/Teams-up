# Autorisations sur les tournois (Pundit).
# Lecture publique (index/show) ; création réservée aux connectés ;
# modification/suppression réservées au créateur (admin du tournoi).
class TournamentPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  # Page d'attente publique (feature en chantier) : accessible à tous.
  def coming_soon?
    true
  end

  def create?
    user.present?
  end

  # Autocomplete de recherche d'utilisateurs (co-organisateur) : mêmes droits que
  # la création, puisqu'il n'est utile que dans le formulaire de création.
  def search?
    create?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  # Gestion du tableau (lancer le tournoi, saisir les résultats).
  # Ouverte à l'admin ET aux co-organisateurs (cf. Tournament#organizer?).
  def start?
    manage?
  end

  def manage?
    record.organizer?(user)
  end

  private

  # Le créateur du tournoi en est l'admin.
  def owner?
    record.user == user
  end

  # Tournois visibles : tous, pour tout le monde (pas de tournoi privé au Lot 1).
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
