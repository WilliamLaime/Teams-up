class MatchPolicy < ApplicationPolicy
  # NOTE: Up to Pundit v2.3.1, the inheritance was declared as
  # `Scope < Scope` rather than `Scope < ApplicationPolicy::Scope`.
  # In most cases the behavior will be identical, but if updating existing
  # code, beware of possible changes to the ancestors:
  # https://gist.github.com/Burgestrand/4b4bc22f31c8a95c425fc0e30d7ef1f5
  def create?
    true
  end

  def show?
    true
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  private

  # Vérifie que l'utilisateur connecté est le créateur du match
  def owner?
    record.user == user
  end

  class Scope < ApplicationPolicy::Scope
    # Définit quels matchs sont visibles dans la liste
    # Tout le monde peut voir tous les matchs
    def resolve
      scope.all
    end
  end
end
