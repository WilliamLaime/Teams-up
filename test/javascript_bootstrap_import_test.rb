require "test_helper"

# Garde-fou sur une erreur silencieuse et coûteuse à diagnostiquer.
#
# `bootstrap.min.js` (gem bootstrap) est le build **UMD** : il n'expose AUCUN
# export ESM et se contente de peupler `window.bootstrap`. Un
# `import * as bootstrap from "bootstrap"` renvoie donc un namespace VIDE — et,
# pire, il MASQUE le global dans la portée du module. `bootstrap.Modal` vaut alors
# `undefined`, sans le moindre message au chargement : l'erreur ne se manifeste
# qu'au premier appel, en plein milieu d'une interaction.
#
# Symptômes réellement constatés : tooltips morts, dispose() des modales inopérant
# (backdrop absent après une navigation Turbo) et surtout la confirmation
# `data-turbo-confirm` qui levait une exception, ce qui ANNULAIT silencieusement la
# soumission — le bouton « Forfait » d'un tournoi ne faisait plus rien.
#
# Un test de rendu ne peut pas attraper ça (le HTML est correct) et la suite ne
# tourne pas de navigateur. D'où cette vérification statique, à trois sous.
class JavascriptBootstrapImportTest < ActiveSupport::TestCase
  JS_ROOT = Rails.root.join("app/javascript")

  test "aucun fichier JS n'importe bootstrap en namespace ESM" do
    offenders = Dir.glob(JS_ROOT.join("**/*.js")).select do |path|
      # On ignore les lignes de commentaire : ce fichier-ci comme application.js
      # citent volontairement la forme fautive pour l'expliquer.
      File.readlines(path).any? do |line|
        line.match?(/^\s*import\s+\*\s+as\s+\w+\s+from\s+["']bootstrap["']/)
      end
    end

    assert_empty offenders.map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s },
                 "bootstrap.min.js est un build UMD sans export ESM : utiliser " \
                 "`import \"bootstrap\"` puis lire `window.bootstrap`."
  end

  test "application.js lit bootstrap depuis le global et jamais depuis un binding local" do
    source = File.read(JS_ROOT.join("application.js"))
    code   = source.lines.reject { |line| line.strip.start_with?("//") }.join

    # Toute utilisation de Modal / Offcanvas / Tooltip doit être qualifiée par
    # `window.` — sinon on retombe sur un binding qui peut être masqué.
    unqualified = code.scan(/(?<!window\.)bootstrap\.(Modal|Offcanvas|Tooltip|Dropdown|Collapse)/)

    assert_empty unqualified,
                 "Qualifier ces accès avec `window.bootstrap` dans application.js " \
                 "(le module importe bootstrap pour ses effets de bord uniquement)."
  end
end
