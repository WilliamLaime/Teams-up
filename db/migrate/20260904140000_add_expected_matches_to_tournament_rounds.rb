# ── Combien de matchs un tour doit-il compter ? ───────────────────────────────
# Jusqu'ici, `TournamentRound#complete?` valait « tous mes matchs sont joués ».
# C'était suffisant parce qu'un tour naissait TOUJOURS d'un bloc : on ne pouvait
# donc pas confondre « tour terminé » et « tour à peine commencé ».
#
# Les tableaux du Critérium Fédéral se construisent désormais AU FUR ET À MESURE
# (une demi-finale naît dès que ses deux quarts sont joués, cf.
# BracketBuilder#advance! en mode incrémental) : un tour peut exister avec un
# seul de ses deux matchs. Sans cette colonne, ce tour passerait pour complet,
# CriteriumFlow#close_finished_rounds! le VERROUILLERAIT (status "completed", cf.
# TournamentMatchPolicy#update?) et le match ajouté ensuite serait injouable.
#
# Nullable et sans défaut, volontairement : `nil` signifie « tour généré d'un
# bloc » (poules, ronde suisse, championnat, barrages) et conserve exactement la
# sémantique historique. Seuls les tours de tableau la renseignent.
#
# ── Le backfill n'est pas cosmétique ─────────────────────────────────────────
# Un Critérium DÉJÀ lancé a des tours de tableau en base. Les laisser à `nil`
# tandis que le nouveau BracketBuilder complète leur successeur au fur et à
# mesure reproduirait exactement le verrouillage décrit ci-dessus. On dérive donc
# la valeur sans rien connaître de CriteriumStructure : dans une suite de tours
# (tournoi, phase, branche), le tour 1 est toujours créé INTÉGRALEMENT par
# BracketBuilder#build! (byes inclus), et un tableau divise son effectif par deux
# à chaque tour — d'où expected(n) = matches(tour 1) / 2**(n-1).
class AddExpectedMatchesToTournamentRounds < ActiveRecord::Migration[8.1]
  BRACKET_PHASES = %w[bracket consolation classification].freeze

  def up
    add_column :tournament_rounds, :expected_matches, :integer

    TournamentRound.reset_column_information

    TournamentRound.where(phase: BRACKET_PHASES)
                   .group_by { |round| [round.tournament_id, round.phase, round.branch] }
                   .each_value { |rounds| backfill_series(rounds) }
  end

  def down
    remove_column :tournament_rounds, :expected_matches
  end

  private

  def backfill_series(rounds)
    rounds = rounds.sort_by(&:number)
    first  = rounds.first
    base   = first.tournament_matches.count
    return if base.zero?

    rounds.each do |round|
      # Le numéro de tour est absolu dans la suite : on le ramène au rang du
      # premier tour connu, sinon une suite tronquée (tour 1 supprimé par une
      # correction) diviserait par une puissance trop grande.
      expected = base / (2**(round.number - first.number))
      round.update_column(:expected_matches, [expected, 1].max)
    end
  end
end
