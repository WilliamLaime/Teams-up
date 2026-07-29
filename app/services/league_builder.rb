# ── Service LeagueBuilder ─────────────────────────────────────────────────────
# Moteur du format « Championnat » (Lot 5) : round-robin intégral (tout le monde
# s'affronte une fois). Deux variantes selon Tournament#playoffs? (Lot 6) : AVEC
# playoffs, les meilleurs entrent dans un tableau final ; SANS, le tournoi se termine
# à la dernière journée et le vainqueur est le 1er du classement (Tournament#champion).
#
# Deux responsabilités, comme SwissPairing :
#   • .schedule  : l'ALGORITHME PUR (méthode du cercle / Berger). Aucun accès base.
#     Renvoie le calendrier COMPLET : une entrée par journée, chaque journée étant
#     une liste de paires [a, b] (a ou b peut être nil = bye si effectif impair).
#   • #next_round! : la PERSISTANCE. Génère UNE journée à la fois (comme la ronde
#     suisse) : la journée N+1 n'est créée que lorsque la N est terminée. Quand
#     toutes les journées sont jouées, bascule sur le tableau final (top-N) ou termine
#     directement le tournoi, selon #playoffs?.
#
# Le calendrier étant déterministe, on le recalcule à chaque appel et on ne
# persiste que la prochaine journée manquante — à condition que l'ordre des
# joueurs soit STABLE (indépendant des résultats), d'où #ordered_players trié par
# draw_order (le tirage au sort figé une fois pour toutes au lancement du tournoi).
class LeagueBuilder
  # Recalcul du bilan V/D + sets/points (sans état suisse : apply_state: false).
  include RoundRobinStats

  def initialize(tournament)
    @tournament = tournament
  end

  # ── Algorithme pur : calendrier round-robin (méthode du cercle) ───────────────
  # @param players [Array] joueurs (objets quelconques ou nil pour le padding)
  # @return [Array<Array<[a, b]>>] une entrée par journée (indexée 0..N-2)
  def self.schedule(players)
    ring = players.dup
    ring << nil if ring.size.odd? # bye tournant si effectif impair
    n = ring.size
    return [] if n < 2

    (n - 1).times.map do
      pairs = (n / 2).times.map { |i| [ring[i], ring[n - 1 - i]] }
      # On fixe le 1er élément et on fait tourner le reste (rotation du cercle).
      ring = [ring[0]] + ring[2..] + [ring[1]]
      pairs
    end
  end

  # ── Persistance ───────────────────────────────────────────────────────────────
  # Génère la journée suivante (ou la première), ou bascule sur les playoffs.
  # Idempotent : ne crée rien tant que la journée courante n'est pas terminée.
  def next_round!
    ActiveRecord::Base.transaction do
      current = @tournament.current_round
      # Journée en cours non terminée → on ne génère rien (protège des double-clics).
      return current if current && !current.complete?

      current&.update!(status: "completed")

      # Les playoffs ont déjà commencé → on les fait avancer (tour suivant / fin).
      return BracketBuilder.new(@tournament).advance! if @tournament.bracket_started?

      # Recalcul du bilan V/D (sans logique suisse : le classement décide, pas 3 V/3 D).
      recompute_stats_for("league", apply_state: false)

      full       = self.class.schedule(ordered_players)
      next_index = @tournament.league_rounds.count

      if next_index < full.size
        create_league_round!(number: next_index + 1, pairs: full[next_index])
      elsif @tournament.playoffs?
        start_playoffs!
      else
        # Championnat SANS playoffs (Lot 6) : la dernière journée jouée termine le
        # tournoi directement — le vainqueur est le 1er du classement (cf. Tournament#champion).
        @tournament.update!(status: "completed")
      end
    end
  end

  private

  # Ordre STABLE des joueurs (par draw_order, le tirage au sort figé au lancement —
  # cf. TournamentsController#assign_draw_order!) : garantit un calendrier
  # reproductible d'un appel à l'autre, indépendamment des scores déjà saisis, sans
  # pour autant reproduire l'ordre d'inscription (id).
  def ordered_players = player_scope.order(:draw_order).to_a

  # Crée une journée (phase "league") et ses matchs (bye et forfait gérés par
  # build_match!).
  def create_league_round!(number:, pairs:)
    round = @tournament.tournament_rounds.create!(phase: "league", number: number, status: "in_progress")
    pairs.each_with_index { |(a, b), position| build_match!(round, a, b, position) }
    round
  end

  # Bascule sur le tableau final : les meilleurs du classement (top final_size)
  # deviennent les finalistes (marqués "qualified" pour le badge du classement).
  def start_playoffs!
    finalists = @tournament.ranked_players.first(@tournament.final_size)
    finalists.each { |tu| tu.update!(state: "qualified") }
    BracketBuilder.new(@tournament, finalists: finalists).build!
  end
end
