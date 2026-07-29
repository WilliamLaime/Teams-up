# ── Modèle TournamentMatch ────────────────────────────────────────────────────
# Un match d'un tournoi : oppose deux inscriptions (tournament_users).
# player_b nul = bye (exempt) → player_a est déclaré vainqueur d'office.
#
# Lot 4 : on stocke le score set-par-set dans la colonne jsonb `sets`
# (ex. [[6, 4], [3, 6], [7, 5]] = paires [jeux_a, jeux_b]) et on en DÉRIVE le
# vainqueur (celui qui remporte assez de sets selon les règles du sport). Le score
# reste modifiable tant que la ronde n'est pas verrouillée (garde côté controller).
class TournamentMatch < ApplicationRecord
  belongs_to :tournament_round
  belongs_to :player_a, class_name: "TournamentUser"
  belongs_to :player_b, class_name: "TournamentUser", optional: true
  belongs_to :winner,   class_name: "TournamentUser", optional: true
  # Joueur ayant abandonné (forfait, Lot 5) — l'autre gagne d'office.
  belongs_to :retired_player, class_name: "TournamentUser", optional: true

  has_one :tournament, through: :tournament_round

  # Rencontre standard planifiée pour cette carte (Lot 4) — optionnelle.
  # nullify : supprimer la carte ne détruit pas la rencontre (chat, inscriptions).
  has_one :match, dependent: :nullify

  STATUSES = %w[pending completed].freeze

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate  :winner_is_a_player
  validate  :sets_valid_for_sport

  # Un bye est gagné d'office par player_a dès sa création.
  before_validation :resolve_bye, on: :create
  # Le vainqueur découle du score : recalculé avant chaque sauvegarde.
  before_save :derive_winner_from_sets

  # ── Écriture du score ─────────────────────────────────────────────────────────
  # Normalise puis affecte le détail set-par-set. `raw` = tableau de paires
  # (venant du formulaire) ; les lignes vides / incomplètes sont ignorées.
  def assign_score(raw)
    self.sets = normalize_sets(raw)
  end

  # ── Lecture ─────────────────────────────────────────────────────────────────
  # Match décidé : un vainqueur est connu (inclut les byes).
  def decided? = winner_id.present?

  # Match nul (Lot 6) : résultat définitif mais sans vainqueur (foot/hand uniquement).
  def draw? = status == "completed" && winner_id.blank? && !is_bye

  # Un score set-par-set a-t-il été saisi ?
  def score_entered? = normalized_sets.any?

  # Les deux inscriptions en lice (compacte le bye).
  def players = [player_a, player_b].compact

  # Le perdant (nil sur un bye ou un match non décidé).
  def loser
    return nil if is_bye || winner_id.blank?

    winner_id == player_a_id ? player_b : player_a
  end

  # L'adversaire de `player` dans ce match (nil si `player` n'y joue pas ou bye).
  def opponent_of(player)
    return nil if player.nil?

    players.find { |p| p.id != player.id }
  end

  # Score global en sets, côté A d'abord (ex. "2-1"). nil si rien de saisi.
  def sets_summary
    return nil unless score_entered?

    "#{sets_won_by(player_a)}-#{sets_won_by(player_b)}"
  end

  # Score à AFFICHER pour `player` : en mode :sets (raquette), nombre de sets
  # remportés (ex. 2 sets à 0) ; en mode :score (collectif), le score réel marqué
  # (ex. 3 buts) — PAS sets_won_by, qui vaudrait toujours 0 ou 1 en mode :score
  # (une seule "paire" stockée = le score final) et afficherait donc "1-0"/"0-0"
  # au lieu du vrai score.
  def display_score_for(player)
    scoring_rules[:mode] == :score ? points_won_by(player) : sets_won_by(player)
  end

  # Score global affiché, côté A d'abord (ex. "2-1" en sets, "3-2" en buts pour un
  # sport à score simple). nil si rien de saisi.
  def score_summary
    return nil unless score_entered?

    "#{display_score_for(player_a)}-#{display_score_for(player_b)}"
  end

  # Nombre de sets remportés par l'inscription `player` (0 si elle ne joue pas ici).
  def sets_won_by(player)
    side = side_of(player)
    return 0 if side.nil?

    normalized_sets.count { |a, b| side == :a ? a > b : b > a }
  end

  # Total de jeux/points marqués par `player` sur l'ensemble des sets.
  def points_won_by(player)
    side = side_of(player)
    return 0 if side.nil?

    normalized_sets.sum { |a, b| side == :a ? a : b }
  end

  # Total de jeux/points concédés par `player` (= marqués par l'adversaire).
  def points_lost_by(player)
    points_won_by(opponent_of(player))
  end

  private

  # ── Dérivation du vainqueur ───────────────────────────────────────────────────
  # Deux modes selon le sport (cf. Sport#scoring_rules) :
  #   :sets  (raquette) — le vainqueur est celui qui atteint le nombre de sets requis.
  #   :score (collectif) — un seul score final, un nul est possible si le sport
  #     l'autorise (match "completed" mais sans vainqueur).
  # Score insuffisant → match remis en attente (winner nil, status pending). Les byes
  # sont intacts. Forfait (Lot 5) : l'adversaire du joueur ayant abandonné gagne d'office.
  def derive_winner_from_sets
    return if is_bye

    if forfeit
      self.winner_id = forfeit_winner_id
      self.status = "completed"
      return
    end

    if scoring_rules[:mode] == :score
      derive_winner_from_final_score
    else
      derive_winner_from_sets_count
    end
  end

  # Mode :score — le score final unique (1 paire) décide directement.
  def derive_winner_from_final_score
    pair = normalized_sets.first
    return set_pending! if pair.nil?

    a, b = pair
    if a == b
      # Nul : résultat définitif, pas de vainqueur (cf. Sport#scoring_rules[:allow_draw],
      # déjà garanti par la validation sets_valid_for_sport).
      self.winner_id = nil
      self.status = "completed"
    elsif a > b
      self.winner_id = player_a_id
      self.status = "completed"
    else
      self.winner_id = player_b_id
      self.status = "completed"
    end
  end

  # Mode :sets — le vainqueur est celui qui atteint le nombre de sets requis (best_of / 2 + 1).
  def derive_winner_from_sets_count
    needed = sets_to_win
    a = sets_won_by(player_a)
    b = sets_won_by(player_b)

    if a >= needed
      self.winner_id = player_a_id
      self.status = "completed"
    elsif b >= needed
      self.winner_id = player_b_id
      self.status = "completed"
    else
      set_pending!
    end
  end

  def set_pending!
    self.winner_id = nil
    self.status = "pending"
  end

  # Vainqueur d'un forfait : l'adversaire du joueur ayant abandonné. Si le joueur
  # abandonnaire n'est pas identifié, on ne décide rien (winner nil).
  def forfeit_winner_id
    return nil if retired_player_id.blank?

    retired_player_id == player_a_id ? player_b_id : player_a_id
  end

  # Sets nécessaires pour gagner le match selon le sport (best_of 3 → 2, best_of 5 → 3).
  def sets_to_win = (scoring_rules[:best_of] / 2) + 1

  # Règles de score du sport du tournoi (fallback sûr si le sport est absent).
  def scoring_rules
    tournament&.sport&.scoring_rules || Sport.new.scoring_rules
  end

  # ── Validations ───────────────────────────────────────────────────────────────
  # Le vainqueur doit être l'un des deux joueurs du match.
  def winner_is_a_player
    return if winner_id.blank?
    return if winner_id == player_a_id || winner_id == player_b_id

    errors.add(:winner, "doit être l'un des deux joueurs du match")
  end

  # Contrôle le score selon les règles du sport. Tolérant (contexte amateur) mais
  # bloque les scores aberrants — et les nuls, sauf pour les sports qui les autorisent.
  def sets_valid_for_sport
    return if is_bye || normalized_sets.empty?

    rules = scoring_rules
    rules[:mode] == :score ? validate_final_score(rules) : validate_sets(rules)
  end

  # Mode :score — un seul couple de scores attendu ; nul rejeté sauf allow_draw.
  def validate_final_score(rules)
    if normalized_sets.size > 1
      errors.add(:sets, "un seul score final est attendu pour ce sport")
      return
    end

    a, b = normalized_sets.first
    errors.add(:sets, "le match nul n'est pas autorisé pour ce sport") if a == b && !rules[:allow_draw]
  end

  # Mode :sets — contrôle chaque set (dont la règle des 2 points d'écart). Un set
  # ne peut jamais être nul (indépendant du sport, propre à la mécanique des sets).
  def validate_sets(rules)
    if normalized_sets.size > rules[:best_of]
      errors.add(:sets, "comporte trop de sets (maximum #{rules[:best_of]})")
      return
    end

    normalized_sets.each_with_index do |(a, b), index|
      if a == b
        errors.add(:sets, "set #{index + 1} : un set ne peut pas être nul")
      elsif !valid_set?(a, b, rules)
        errors.add(:sets, "set #{index + 1} : score invalide (#{a}-#{b})")
      end
    end
  end

  # Un set est valide si le vainqueur atteint la cible avec 2 points d'écart
  # (ou pile au plafond, où 1 point suffit — tie-break).
  def valid_set?(games_a, games_b, rules)
    hi = [games_a, games_b].max
    lo = [games_a, games_b].min
    return false if hi < rules[:target]
    return true  if rules[:cap] && hi >= rules[:cap]
    return true  unless rules[:win_by_two]

    (hi - lo) >= 2
  end

  # ── Helpers de score ──────────────────────────────────────────────────────────
  # De quel côté joue `player` : :a, :b, ou nil s'il ne joue pas dans ce match.
  def side_of(player)
    return nil if player.nil?
    return :a if player.id == player_a_id
    return :b if player.id == player_b_id

    nil
  end

  # Sets normalisés : tableau de paires d'entiers, lignes vides/incomplètes exclues.
  def normalized_sets = normalize_sets(sets)

  def normalize_sets(raw)
    Array(raw).filter_map do |pair|
      values = Array(pair).map { |v| v.to_s.strip }
      next if values.size != 2 || values.any?(&:blank?)

      values.map(&:to_i)
    end
  end

  # Bye : pas d'adversaire → player_a gagne, match clôturé immédiatement.
  def resolve_bye
    return unless is_bye

    self.player_b_id = nil
    self.winner_id ||= player_a_id
    self.status = "completed"
  end
end
