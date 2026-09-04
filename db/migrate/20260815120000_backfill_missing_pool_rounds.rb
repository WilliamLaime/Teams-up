# Rattrapage de données — calendrier de poules incomplet.
#
# Avant ce lot, PoolBuilder ne créait la journée N+1 qu'une fois la journée N
# entièrement jouée : un tournoi en cours n'avait donc que ses premières journées
# en base, et un joueur de poule de 4 ne voyait qu'un seul de ses 3 adversaires.
# PoolBuilder crée désormais TOUT le calendrier au lancement (règle : poule de N
# → N-1 rencontres par joueur), mais les tournois DÉJÀ lancés restent amputés
# jusqu'au prochain appel du moteur — c'est-à-dire jusqu'à un score qui termine
# une journée. Cette migration provoque cet appel une fois pour toutes.
#
# Aucune écriture directe ici : on relaie au moteur, qui sait seul quoi créer et
# reste idempotent (create_missing_pool_rounds! est écrit comme un rattrapage).
# Ses gardes internes protègent les tournois qui ne doivent pas bouger — phase
# finale entamée, tableau lancé — et un tournoi déjà complet ne gagne rien.
#
# Irréversible par nature (on ne peut pas deviner quelles journées étaient
# « en trop »), d'où le `up` seul.
class BackfillMissingPoolRounds < ActiveRecord::Migration[8.1]
  def up
    Tournament.where(format: Tournament::POOL_BASED_FORMATS, status: "in_progress").find_each do |tournament|
      TournamentEngine.for(tournament).next_round!
    rescue StandardError => e
      # Un tournoi bancal (poules non attribuées, données de test incohérentes)
      # ne doit pas bloquer le déploiement : on le signale et on continue.
      say "Tournoi ##{tournament.id} ignoré : #{e.class} — #{e.message}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
