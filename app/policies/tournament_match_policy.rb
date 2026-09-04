# Autorisations sur un match de tournoi (Lot 4 — saisie du score, Lot 7 —
# planification de la rencontre par les joueurs).
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

  # Planifier la rencontre réelle (modèle Match) de cette confrontation : ouvert
  # aux DEUX joueurs concernés en plus des organisateurs, pour qu'ils conviennent
  # eux-mêmes de la date et de l'heure sans dépendre de l'admin. Un seul Match par
  # confrontation (index unique sur matches.tournament_match_id) : le premier des
  # deux joueurs à créer la rencontre ferme la porte, l'autre voit « Voir la rencontre ».
  # Un bye n'a pas de rencontre à jouer.
  def create_match?
    return false if user.blank?
    return false if record.is_bye || record.match.present?

    record.tournament.organizer?(user) || player_of_match?
  end

  # Chat d'organisation de la confrontation : mêmes ayants droit que la
  # planification ci-dessus — les DEUX joueurs, plus l'admin et les
  # co-organisateurs (qui doivent pouvoir arbitrer un désaccord sur la date).
  # Personne d'autre : le fil est privé à la confrontation, et c'est ce qui le
  # rend utilisable pour convenir d'un créneau.
  #
  # Un bye n'a pas d'adversaire, donc personne avec qui s'organiser.
  # Contrairement à create_match?, la présence d'une rencontre déjà planifiée ne
  # ferme PAS le chat : une date se déplace, et c'est là qu'on en discute.
  def chat?
    return false if user.blank?
    return false if record.is_bye

    record.tournament.organizer?(user) || player_of_match?
  end

  # Correction d'un score même après verrouillage du tour (Lot 5).
  # Réservée à l'organisateur : contourne délibérément le verrou de update?,
  # avec régénération de l'aval côté controller.
  def correct?
    user.present? && record.tournament.organizer?(user)
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
