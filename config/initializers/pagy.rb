# Initializer Pagy — charge les extras nécessaires
# pagy/extras/bootstrap → fournit pagy_bootstrap_nav() pour les vues
# pagy/extras/array    → permet de paginer des tableaux Ruby simples
# pagy/extras/overflow → évite un 500 quand on demande une page inexistante
#                        (?page=999) : on retombe sur la dernière page valide.
require "pagy/extras/bootstrap"
require "pagy/extras/overflow"
Pagy::DEFAULT[:overflow] = :last_page
