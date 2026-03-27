class MatchVote < ApplicationRecord
  # ── Associations ─────────────────────────────────────────────────────────
  belongs_to :voter, class_name: "User" # celui qui vote
  belongs_to :match
  belongs_to :voted_for, class_name: "User" # le candidat élu

  # ── Validations ──────────────────────────────────────────────────────────

  # Un seul vote par votant par match
  validates :voter_id, uniqueness: {
    scope: :match_id,
    message: "a déjà voté pour ce match"
  }

  # Interdire de voter pour soi-même
  validate :cannot_vote_for_yourself

  # Les deux joueurs doivent avoir participé au match (status: approved)
  validate :both_players_must_have_played

  # Vote ouvert uniquement dans les 7 jours suivant la fin du match
  validate :within_vote_window

  # ── Callbacks ────────────────────────────────────────────────────────────

  # Recalcule l'homme du match à chaque création/suppression de vote
  after_create  :recalculate_homme_du_match
  after_destroy :recalculate_homme_du_match

  private

  # Empêche un joueur de voter pour lui-même
  def cannot_vote_for_yourself
    return unless voter_id == voted_for_id

    errors.add(:base, "Vous ne pouvez pas voter pour vous-même.")
  end

  # Vérifie que voter et voted_for ont bien participé au match (status approved)
  def both_players_must_have_played
    return unless match && voter && voted_for

    unless match.match_users.where(user_id: voter_id, status: "approved").exists?
      errors.add(:base, "Vous n'avez pas participé à ce match.")
    end

    return if match.match_users.where(user_id: voted_for_id, status: "approved").exists?

    errors.add(:base, "Ce joueur n'a pas participé à ce match.")
  end

  # Vérifie que le match est bien terminé ET dans la fenêtre de 7 jours
  def within_vote_window
    return unless match

    unless match.completed?
      errors.add(:base, "Ce match n'est pas encore terminé.")
      return
    end

    # Reconstruit le datetime du match pour calculer la fenêtre
    match_datetime = Time.zone.local(
      match.date.year, match.date.month, match.date.day,
      match.time.hour, match.time.min, 0
    )

    return unless Time.current > match_datetime + 7.days

    errors.add(:base, "La fenêtre de vote (7 jours) est dépassée.")
  end

  # Recalcule qui a le plus de votes dans ce match et met à jour :
  #   - match.homme_du_match_id  (le nouveau gagnant)
  #   - profil.homme_du_match_count de l'ancien et du nouveau gagnant
  def recalculate_homme_du_match
    # Compte les votes par candidat pour ce match
    vote_counts = MatchVote.where(match: match).group(:voted_for_id).count

    # Le candidat avec le plus de votes (nil si aucun vote)
    new_winner_id = vote_counts.max_by { |_, count| count }&.first

    old_winner_id = match.homme_du_match_id

    # Rien à faire si le gagnant n'a pas changé
    return if old_winner_id == new_winner_id

    # Met à jour le gagnant sur le match
    match.update_columns(homme_du_match_id: new_winner_id)

    # Décrémente le compteur de l'ancien gagnant (plancher à 0)
    if old_winner_id
      old_profil = User.find(old_winner_id).profil
      old_profil&.update_columns(
        homme_du_match_count: [old_profil.homme_du_match_count.to_i - 1, 0].max
      )
    end

    # Incrémente le compteur du nouveau gagnant
    return unless new_winner_id

    new_profil = User.find(new_winner_id).profil
    new_profil&.update_columns(
      homme_du_match_count: new_profil.homme_du_match_count.to_i + 1
    )
  end
end
