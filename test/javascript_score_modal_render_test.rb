require "test_helper"

# Garde-fou sur un bug de saisie qu'aucun test de rendu ne peut attraper.
#
# La modale de score recalcule le nombre de lignes de sets à CHAQUE frappe. La 1re
# version reconstruisait tout le bloc (`rowsTarget.innerHTML = ""`) puis rendait le
# focus à l'input qui l'avait. L'élément refocalisé était le bon, mais un input
# fraîchement créé replace son caret en position 0 : taper « 13 » quand le 1er
# chiffre complète un set (donc fait apparaître une ligne) écrivait « 31 ».
#
# Le correctif est un rendu incrémental — on n'ajoute/retire que des lignes en fin de
# liste, et on ne recrée jamais le champ en cours de frappe. Ces assertions verrouillent
# cet invariant : c'est de la vérification de FORME, assumée comme telle. Un test
# comportemental exigerait Selenium + Chrome (la suite tourne en :rack_test).
class JavascriptScoreModalRenderTest < ActiveSupport::TestCase
  CONTROLLER = Rails.root.join("app/javascript/controllers/tournament_score_controller.js")

  # Le fichier COMMENTE volontairement la forme fautive pour l'expliquer : les
  # assertions doivent donc porter sur le code seul.
  def code
    @code ||= File.readlines(CONTROLLER)
                  .reject { |line| line.strip.start_with?("//") }
                  .join
  end

  test "les lignes de sets ne sont détruites que par resetRows, hors chemin de frappe" do
    assert_equal 1, code.scan(/rowsTarget\.innerHTML\s*=\s*""/).size,
                 "Un seul effacement du bloc de lignes est admis, dans resetRows."

    # Le corps de resetRows, jusqu'à l'accolade fermante de la méthode.
    reset_body = code[/^  resetRows\(sets\) \{.*?^  \}/m]
    assert reset_body, "resetRows(sets) doit exister : c'est le seul rendu complet."
    assert_match(/rowsTarget\.innerHTML\s*=\s*""/, reset_body,
                 "L'effacement doit être DANS resetRows (appelé par open, modale non visible).")
  end

  test "aucun focus() programmatique : le champ en cours de frappe n'est jamais recréé" do
    refute_match(/\.focus\(\)/, code,
                 "Restaurer le focus signifie qu'on a détruit les inputs — c'est le bug d'origine.")
  end

  test "refreshRows réconcilie les lignes et met le compteur à jour à chaque frappe" do
    body = code[/^  refreshRows\(\) \{.*?^  \}/m]
    assert body, "refreshRows() doit exister : c'est le handler branché sur `input`."

    assert_match(/this\.syncRows\(/, body, "refreshRows doit passer par syncRows (rendu incrémental).")
    assert_match(/this\.updateTally\(/, body, "Le compteur de sets doit suivre CHAQUE frappe.")
  end
end
