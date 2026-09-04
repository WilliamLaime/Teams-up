# Autorisations sur les inscriptions à un tournoi (Pundit).
class TournamentUserPolicy < ApplicationPolicy
  # Tout utilisateur connecté peut s'inscrire à un tournoi.
  def create?
    user.present?
  end

  # Retrait d'une inscription — une DÉSINSCRIPTION SÈCHE : la ligne disparaît,
  # rien à voir avec le forfait (cf. #withdraw?). Deux personnes peuvent la
  # déclencher : l'inscrit lui-même, et l'organisation du tournoi.
  def destroy?
    return false if user.blank?
    # Garde STRUCTURELLE, pas cosmétique : `tournament_matches` porte quatre clés
    # étrangères vers `tournament_users` (player_a_id, player_b_id, winner_id,
    # retired_player_id). Détruire une inscription d'un tournoi lancé lèverait
    # donc une PG::ForeignKeyViolation — une 500. Une fois le tableau généré, la
    # seule sortie possible est le forfait.
    return false unless record.tournament.open? || record.tournament.closed?
    # On se désinscrit toujours soi-même.
    return true if record.user == user

    # L'organisation ne retire que de SIMPLES joueurs. Sans la seconde condition,
    # un co-organisateur pourrait désinscrire l'admin ou un pair — exactement la
    # faille déjà fermée par TournamentPolicy#manage_organizers?. Pour retirer un
    # co-organisateur, l'admin le révoque d'abord (TournamentsController#remove_co_organizer),
    # ce qui le ramène au rang de simple joueur, puis le désinscrit.
    record.tournament.organizer?(user) && !record.tournament.organizer?(record.user)
  end

  # Déclarer le forfait d'un joueur : réservé à l'organisateur (admin ou co-org).
  def withdraw?
    user.present? && record.tournament.organizer?(user)
  end
end
