# Autorisations sur un match de tournoi (Lot 4 — saisie du score).
# La saisie/modification du score est ouverte à 4 rôles : l'admin et les
# co-organisateurs du tournoi (via Tournament#organizer?), ainsi que les DEUX
# joueurs du match. Elle reste possible tant que le tour n'est pas verrouillé
# (sa ronde n'est pas "completed" — cf. clôture automatique dans SwissPairing).
class TournamentMatchPolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    return false if user.blank?
    return false if record.tournament_round.status == "completed" # tour verrouillé

    record.tournament.organizer?(user) || player_of_match?
  end

  private

  # L'utilisateur courant est-il l'un des deux joueurs de ce match ?
  def player_of_match?
    [record.player_a&.user_id, record.player_b&.user_id].include?(user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
