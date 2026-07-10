# Lot 4 — Couplage de la rencontre Match standard aux tournois.
#   • tournament_id       : association LÂCHE (« ce match fait partie du tournoi X »),
#     choisie dans le formulaire de création de match.
#   • tournament_match_id : lien PRÉCIS 1↔1 avec une carte du tableau (index unique →
#     un TournamentMatch n'a qu'une seule rencontre planifiée).
# Les deux FK vivent sur `matches` (le côté qui référence optionnellement le tournoi) :
# un Match peut exister sans tournoi, un TournamentMatch sans rencontre.
class AddTournamentRefsToMatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :matches, :tournament,       null: true, foreign_key: true, index: true
    add_reference :matches, :tournament_match, null: true, foreign_key: true, index: { unique: true }
  end
end
