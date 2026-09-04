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
    # Le Critérium Fédéral commence par une phase de poules identique au format
    # "poules" : même répartition, même calendrier round-robin. C'est seulement à la
    # bascule en phase finale que PoolBuilder délègue à CriteriumFlow (barrages,
    # tableau final, consolante, matchs de classement).
    when "poules", "criterium_federal" then PoolBuilder.new(tournament)
    else SwissPairing.new(tournament) # ronde_suisse + défaut sûr
    end
  end
end
