class Avis < ApplicationRecord
  # ── Associations ──────────────────────────────────────────────────────────
  belongs_to :reviewer,      class_name: "User"  # celui qui note
  belongs_to :reviewed_user, class_name: "User"  # celui qui est noté
  belongs_to :match

  # ── Validations ───────────────────────────────────────────────────────────
  # Note obligatoire, doit être entre 1 et 5
  validates :rating, presence: true, inclusion: { in: 1..5, message: "doit être entre 1 et 5" }

  # Un seul avis possible par reviewer pour la même personne dans le même match
  validates :reviewer_id, uniqueness: {
    scope: %i[reviewed_user_id match_id],
    message: "Vous avez déjà laissé un avis pour ce joueur dans ce match."
  }

  # Règles métier personnalisées
  validate :cannot_review_yourself
  validate :both_players_must_have_played
  validate :within_review_window

  # ── Callbacks ─────────────────────────────────────────────────────────────
  # Recalcule la moyenne du profil noté après chaque création ou suppression
  after_create  :recalculate_average
  after_destroy :recalculate_average

  # Maintient le flag mutual quand un nouvel avis est créé ou supprimé
  after_create  :set_mutual_flag
  after_destroy :clear_mutual_flag

  # ── Scopes ────────────────────────────────────────────────────────────────

  # Retourne les avis récents en premier
  scope :recent, -> { order(created_at: :desc) }

  # Avis mutuels : l'avis A→B n'est visible que si B→A existe pour le même match.
  # La colonne booléenne 'mutual' est maintenue par les callbacks après_create et après_destroy.
  scope :mutual, -> { where(mutual: true) }

  # Avis non-mutuels : l'autre personne n'a pas encore rendu la pareille.
  # Utile pour afficher un compteur "avis en attente" sur son propre profil.
  scope :non_mutual, -> { where(mutual: false) }

  private

  # ── Validations personnalisées ─────────────────────────────────────────────

  # Empêche un utilisateur de se noter lui-même
  def cannot_review_yourself
    return unless reviewer_id.present? && reviewed_user_id.present?

    return unless reviewer_id == reviewed_user_id

    errors.add(:base, "Vous ne pouvez pas vous noter vous-même.")
  end

  # Vérifie que les deux joueurs ont participé au match avec le statut "approved"
  def both_players_must_have_played
    return unless match.present? && reviewer_id.present? && reviewed_user_id.present?

    # Le reviewer doit avoir été approuvé dans ce match
    unless match.match_users.exists?(user_id: reviewer_id, status: "approved")
      errors.add(:base, "Vous ne pouvez pas laisser un avis car vous n'avez pas participé à ce match.")
    end

    # Le joueur noté doit aussi avoir été approuvé dans ce match
    return if match.match_users.exists?(user_id: reviewed_user_id, status: "approved")

    errors.add(:base, "Ce joueur n'a pas participé à ce match.")
  end

  # Vérifie que le match est terminé ET dans la fenêtre de 7 jours
  def within_review_window
    return unless match.present?

    # Le match doit être terminé (débuté il y a plus d'1h)
    unless match.completed?
      errors.add(:base, "Vous ne pouvez laisser un avis qu'après la fin du match.")
      return
    end

    # Calcule la fin du match (heure de début + 1h = "terminé")
    match_end_time = Time.zone.local(
      match.date.year, match.date.month, match.date.day,
      match.time.hour, match.time.min
    ) + 1.hour

    # La fenêtre de 7 jours court à partir de la fin du match
    return unless Time.current > match_end_time + 7.days

    errors.add(:base, "La fenêtre de 7 jours pour laisser un avis est dépassée.")
  end

  # ── Recalcul de la moyenne ─────────────────────────────────────────────────

  # Quand A laisse un avis à B, cela peut rendre l'avis B→A mutuel.
  # On recalcule donc les stats des DEUX utilisateurs impliqués.
  def recalculate_average
    recalculate_for(reviewed_user)  # toujours recalculer le profil noté
    recalculate_for(reviewer)       # recalculer l'autre aussi (B→A peut devenir mutuel)
  end

  # Recalcule la moyenne et le compteur d'avis mutuels pour un utilisateur donné
  def recalculate_for(user)
    profil = user.profil
    return unless profil # sécurité : si l'utilisateur n'a pas encore de profil

    # Seuls les avis mutuels comptent pour la moyenne affichée
    all_ratings = Avis.mutual.where(reviewed_user_id: user.id).pluck(:rating)

    if all_ratings.empty?
      avg   = 0.0
      count = 0
    else
      avg   = (all_ratings.sum.to_f / all_ratings.size).round(1)
      count = all_ratings.size
    end

    # update_columns évite de déclencher les callbacks du profil (plus performant)
    profil.update_columns(average_rating: avg, avis_count: count)
  end

  # ── Maintien du flag mutual ────────────────────────────────────────────────

  # Quand A→B est créé : si B→A existe, les deux deviennent mutuels
  # Utilise update_column pour éviter de déclencher les callbacks (performance)
  def set_mutual_flag
    inverse = Avis.find_by(
      reviewer_id: reviewed_user_id,
      reviewed_user_id: reviewer_id,
      match_id: match_id
    )
    return unless inverse

    update_column(:mutual, true)
    inverse.update_column(:mutual, true)
  end

  # Quand A→B est détruit : si B→A existe, il redevient non-mutuel
  def clear_mutual_flag
    inverse = Avis.find_by(
      reviewer_id: reviewed_user_id,
      reviewed_user_id: reviewer_id,
      match_id: match_id
    )
    inverse&.update_column(:mutual, false)
  end
end
