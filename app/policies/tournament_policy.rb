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

  def create?
    user.present?
  end

  # Autocomplete de recherche d'utilisateurs (co-organisateur / transfert d'admin) :
  # mêmes droits que la création. L'endpoint ne renvoie ni email ni id brut (voir
  # TournamentsController#search), donc rien à restreindre au-delà du login.
  def search?
    create?
  end

  # Édition des infos du tournoi : ouverte à l'admin ET aux co-organisateurs,
  # comme le reste de la gestion du tableau (cf. Tournament#organizer?).
  def update?
    manage?
  end

  def destroy?
    owner?
  end

  # Gestion du tableau (lancer le tournoi, saisir les résultats).
  # Ouverte à l'admin ET aux co-organisateurs (cf. Tournament#organizer?).
  def start?
    manage?
  end

  # Clôturer/rouvrir les inscriptions avant le lancement.
  def toggle_registrations?
    manage?
  end

  # Terminer le tournoi manuellement (abandon, ou fin anticipée).
  def finish?
    manage?
  end

  # Constitution des poules (mode + chapeaux) : réservée à l'organisation, et
  # seulement tant que rien n'est joué — une fois lancé, changer la répartition
  # rebattrait des poules déjà en cours.
  def seeding?
    manage? && (record.open? || record.closed?)
  end

  def manage?
    record.organizer?(user)
  end

  # Composition de l'équipe organisatrice (nommer / révoquer un co-organisateur).
  # Réservée à l'admin, PAS ouverte à `manage?` : sinon un co-organisateur pourrait
  # en coopter d'autres, voire révoquer celui qui l'a nommé — l'admin perdrait le
  # contrôle de son propre tournoi sans jamais pouvoir le reprendre.
  def manage_organizers?
    owner?
  end

  # Transmettre l'administration. Irréversible côté ancien admin (il redevient
  # simple co-organisateur), donc réservée à l'admin en place et sans intérêt sur
  # un tournoi déjà terminé — plus rien ne s'y gère.
  def transfer_ownership?
    owner? && !record.completed?
  end

  private

  # Le créateur du tournoi en est l'admin.
  def owner?
    record.user == user
  end

  # Tournois LISTABLES (index, badges de comptage, recherche) :
  #   • tous les tournois publics ;
  #   • plus, pour un utilisateur connecté, ceux qu'il administre et ceux où il a
  #     une ligne d'inscription (joueur ou co-organisateur).
  #
  # Un tournoi privé auquel on n'appartient pas reste accessible par son lien à
  # token — c'est la garde de TournamentsController#show qui en décide, pas ce
  # scope, exactement comme pour les matchs (cf. MatchPolicy::Scope).
  #
  # Trois `where` sur le même scope : les `.or` restent structurellement
  # compatibles (aucun `joins`, la 3e passe par une sous-requête).
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.publicly_visible if user.blank?

      scope.publicly_visible
           .or(scope.where(user_id: user.id))
           .or(scope.where(id: TournamentUser.where(user_id: user.id).select(:tournament_id)))
    end
  end
end
