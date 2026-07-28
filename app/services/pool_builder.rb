# ── Service PoolBuilder ───────────────────────────────────────────────────────
# Moteur du format « Poules » (Lot 5) : on répartit les joueurs en poules, on joue
# un round-robin DANS chaque poule (journée par journée, toutes poules en parallèle),
# puis les meilleurs de chaque poule entrent en tableau final.
#
# Réutilise l'algorithme de calendrier round-robin de LeagueBuilder (.schedule) et
# le recompute partagé (RoundRobinStats). Une « journée » = une TournamentRound de
# phase "pool" regroupant la journée de MÊME index de toutes les poules (respecte
# l'index unique (tournament_id, phase, number)). La poule d'un match se dérive de
# player_a.pool (pas de colonne dédiée sur le match).
class PoolBuilder
  include RoundRobinStats

  def initialize(tournament)
    @tournament = tournament
  end

  # Génère la journée suivante (ou répartit les poules + journée 1), ou bascule
  # sur le tableau final. Idempotent (même garde-fou anti double-clic que le suisse).
  def next_round!
    ActiveRecord::Base.transaction do
      current = @tournament.current_round
      return current if current && !current.complete?

      current&.update!(status: "completed")

      return BracketBuilder.new(@tournament).advance! if @tournament.bracket_started?

      assign_pools! if pools_unassigned?

      recompute_stats_for("pool", apply_state: false)

      schedules      = pool_schedules
      total_journees = schedules.values.map(&:size).max.to_i
      next_index     = @tournament.pool_rounds.count

      if next_index < total_journees
        create_pool_round!(number: next_index + 1, schedules: schedules, index: next_index)
      else
        start_playoffs!
      end
    end
  end

  private

  # ── Répartition en poules ──────────────────────────────────────────────────────
  # Nombre de poules : délègue à Tournament#pool_count, seule source de vérité
  # (aussi utilisée pour dimensionner le tableau final, cf. Tournament#final_size).
  def pool_count = @tournament.pool_count

  def pools_unassigned? = player_scope.where(pool: nil).exists?

  # Distribution en serpentin sur un ordre stable (par id) → poules équilibrées et
  # calendrier reproductible. Persiste `pool` (0-based) sur chaque inscription.
  def assign_pools!
    count = pool_count
    player_scope.order(:id).to_a.each_with_index do |tu, i|
      row = i / count
      col = i % count
      # Serpentin : on inverse le sens une ligne sur deux.
      pool = row.even? ? col : (count - 1 - col)
      tu.update!(pool: pool)
    end
  end

  # ── Calendrier ──────────────────────────────────────────────────────────────────
  # Calendrier round-robin de chaque poule (ordre stable par id).
  # => { pool_index => [journée = [[a, b], …], …] }
  def pool_schedules
    player_scope.order(:id).to_a.group_by(&:pool).transform_values do |members|
      LeagueBuilder.schedule(members)
    end
  end

  # Crée la journée `number` en concaténant la journée d'index `index` de chaque
  # poule. `position` est un compteur global à la ronde (unicité de (round, position)),
  # les tailles de poules pouvant différer (effectifs « Libre »).
  def create_pool_round!(number:, schedules:, index:)
    round = @tournament.tournament_rounds.create!(phase: "pool", number: number, status: "in_progress")

    position = 0
    schedules.keys.compact.sort.each do |pool_index|
      pairs = schedules[pool_index][index]
      next if pairs.nil? # cette poule a moins de journées (poule plus petite)

      pairs.each do |a, b|
        build_match!(round, a, b, position)
        position += 1
      end
    end

    round
  end

  # ── Bascule playoffs ─────────────────────────────────────────────────────────────
  def start_playoffs!
    finalists = pool_finalists
    finalists.each { |tu| tu.update!(state: "qualified") }
    BracketBuilder.new(@tournament, finalists: finalists).build!
  end

  # Qualifiés : les meilleurs de chaque poule pour remplir final_size, complétés
  # par les meilleurs restants toutes poules confondues si final_size n'est pas
  # divisible par le nombre de poules (effectifs « Libre »).
  def pool_finalists
    per_pool = [@tournament.final_size / pool_count, 1].max

    picked = []
    @tournament.pools.keys.sort.each do |pool_index|
      picked.concat(ranked(@tournament.pools[pool_index]).first(per_pool))
    end

    if picked.size < @tournament.final_size
      remaining = ranked(player_scope.to_a) - picked
      picked.concat(remaining.first(@tournament.final_size - picked.size))
    end

    picked.first(@tournament.final_size)
  end

  # Classement d'un groupe de joueurs — délègue à Tournament#rank_key (Lot 6),
  # source unique de vérité partagée avec ranked_players et BracketBuilder.
  def ranked(players)
    players.sort_by { |tu| @tournament.rank_key(tu) }
  end
end
