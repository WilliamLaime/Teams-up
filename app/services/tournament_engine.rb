# ── TournamentEngine ──────────────────────────────────────────────────────────
# Façade d'aiguillage : renvoie le moteur correspondant au format du tournoi.
# C'est le SEUL endroit où le format aiguille le moteur — les controllers ne
# connaissent que l'interface commune `#next_round!` (idempotent, transactionnel).
#
#   TournamentEngine.for(tournament).next_round!
module TournamentEngine
  def self.for(tournament)
    case tournament.format
    when "championnat" then LeagueBuilder.new(tournament)
    when "poules"      then PoolBuilder.new(tournament)
    else                    SwissPairing.new(tournament) # ronde_suisse + défaut sûr
    end
  end
end
