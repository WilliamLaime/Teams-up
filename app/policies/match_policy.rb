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

  # Modifier / supprimer : le créateur du match, mais aussi l'admin et les
  # co-organisateurs du tournoi auquel il est rattaché (rencontre de tournoi),
  # pour qu'ils puissent corriger une date ou retirer une rencontre sans
  # dépendre du joueur qui l'a créée.
  def update?
    owner? || tournament_organizer?
  end

  def destroy?
    owner? || tournament_organizer?
  end

  # Seul l'organisateur peut passer son match privé en public
  def make_public?
    owner?
  end

  # Seul l'organisateur peut partager son match sur Slack
  def share_on_slack?
    owner?
  end

  private

  # Vérifie que l'utilisateur connecté est le créateur du match
  def owner?
    record.user == user
  end

  # L'utilisateur organise-t-il (admin ou co-organisateur) le tournoi du match ?
  # Faux pour un match indépendant (sans tournoi).
  def tournament_organizer?
    record.tournament.present? && record.tournament.organizer?(user)
  end

  class Scope < ApplicationPolicy::Scope
    # Définit quels matchs sont visibles dans l'index :
    # - Les matchs publics → visibles par tous
    # - Les matchs privés → uniquement si l'user en est l'organisateur
    def resolve
      if user
        scope.where(visibility: ["public", nil])
             .or(scope.where(user: user))
      else
        # Visiteur non connecté → uniquement les matchs publics
        scope.where(visibility: ["public", nil])
      end
    end
  end
end
