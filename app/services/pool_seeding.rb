# ── Service PoolSeeding ───────────────────────────────────────────────────────
# Constitution des poules (Lot 7) : QUI va dans QUELLE poule. Deux modes, et deux
# seulement (cf. Tournament::POOL_SEEDING_MODES) :
#
#   • "random" — serpentin sur l'ordre du tirage au sort. Comportement historique
#     de PoolBuilder#assign_pools!, déplacé ici sans en changer une virgule.
#   • "pots"   — chapeaux. Chaque chapeau numéroté fournit UN joueur par poule ;
#     les joueurs sans chapeau (le « chapeau général ») complètent les poules les
#     moins remplies. Exemple du règlement : 32 joueurs, 8 poules de 4, 2 chapeaux
#     → chapeau 1 = 8 joueurs, chapeau 2 = 8, général = 16 → chaque poule reçoit
#     1 joueur du chapeau 1, 1 du chapeau 2, 2 du général.
#
# Il n'y a NI serpent NI classement individuel : l'application n'a pas de
# classement de joueurs, et les chapeaux (remplis à la main par l'organisateur)
# couvrent le besoin de répartir les têtes de série.
#
# ⚠️ Aucun `shuffle` / `rand` / `Time.now` ici. `draw_order`, figé une fois pour
# toutes au lancement (TournamentsController#assign_draw_order!), est la SEULE
# source d'aléa. C'est ce qui rend la répartition reproductible — condition de
# survie de la correction de score, qui régénère l'aval à l'identique.
class PoolSeeding
  # Pour `ordered_player_scope` : l'ordre stable partagé par tous les moteurs
  # round-robin. Le redéfinir ici en dupliquerait la subtilité (`draw_order` seul
  # ne suffit pas, cf. le commentaire du module) — et une copie finit toujours par
  # diverger de l'originale.
  include RoundRobinStats

  def initialize(tournament)
    @tournament = tournament
  end

  # Persiste `pool` (0-based) sur chaque inscription approuvée.
  def assign!
    return if capacities.empty?

    @tournament.seeded_pots? ? assign_by_pots! : assign_at_random!
  end

  private

  # Taille visée de chaque poule — le PLAN du tournoi (11 joueurs → [4, 4, 3]),
  # seule source de vérité du dimensionnement. Le mode chapeaux doit produire
  # exactement les mêmes tailles que le serpentin, sinon changer de mode
  # changerait la structure du tournoi et pas seulement sa composition.
  def capacities = @tournament.pool_plan

  def ordered_players = ordered_player_scope.to_a

  # ── Mode "random" : serpentin ────────────────────────────────────────────────
  # Poules équilibrées et répartition reproductible : on distribue les joueurs
  # colonne par colonne en inversant le sens une ligne sur deux.
  def assign_at_random!
    count = capacities.size
    ordered_players.each_with_index do |tu, i|
      row = i / count
      col = i % count
      tu.update!(pool: row.even? ? col : (count - 1 - col))
    end
  end

  # ── Mode "pots" : chapeaux ───────────────────────────────────────────────────
  def assign_by_pots!
    pools   = Array.new(capacities.size) { [] }
    players = ordered_players

    seat_pots!(pools, players)
    seat_general!(pools, players)

    pools.each_with_index do |members, index|
      members.each { |tu| tu.update!(pool: index) }
    end
  end

  # Un joueur du chapeau k par poule, chapeaux traités dans l'ordre croissant et
  # joueurs dans l'ordre du tirage. Un chapeau plus grand que le nombre de poules
  # (l'organisateur a coché trop de joueurs) ne perd personne : le surplus n'est
  # simplement pas assis ici, il retombera dans le chapeau général.
  #
  # Les numéros au-delà du nombre de chapeaux déclaré sont ignorés : c'est ce que
  # le panneau AFFICHE (son select ne propose que 1..pot_count, un joueur resté en
  # chapeau 3 après passage à 2 chapeaux y apparaît en « chapeau général »). Le
  # moteur doit dire la même chose que l'écran.
  def seat_pots!(pools, players)
    declared = @tournament.pot_count
    players.group_by(&:pot).except(nil).select { |number, _| number <= declared }.sort.each do |_number, members|
      members.each_with_index do |tu, index|
        next unless index < pools.size && pools[index].size < capacities[index]

        pools[index] << tu
      end
    end
  end

  # Chapeau général : les joueurs sans numéro, plus le surplus des chapeaux trop
  # grands. On les parcourt dans l'ordre du tirage (et non par chapeau) pour que
  # l'ordre reste total, donc la répartition reproductible.
  def seat_general!(pools, players)
    seated = pools.flatten.to_set

    players.reject { |tu| seated.include?(tu) }.each do |tu|
      pools[emptiest_pool(pools)] << tu
    end
  end

  # La poule à qui il reste le plus de places ; à égalité, la première — jamais un
  # départage aléatoire.
  def emptiest_pool(pools)
    (0...pools.size).max_by { |index| [capacities[index] - pools[index].size, -index] }
  end
end
