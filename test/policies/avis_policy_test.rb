require "test_helper"

# Tests de AvisPolicy — vérifie les règles d'autorisation pour créer un avis.
#
# Règles métier testées ici (au niveau policy, pas modèle) :
#   1. L'utilisateur doit être connecté (user != nil)
#   2. On ne peut pas se noter soi-même (user != reviewed_user)
#
# Note : les règles plus fines (les deux joueurs doivent avoir joué, fenêtre de
#        7 jours) sont des validations du modèle Avis — pas de la policy.
class AvisPolicyTest < ActiveSupport::TestCase
  def setup
    @reviewer      = users(:one)  # celui qui note
    @reviewed_user = users(:two)  # celui qui est noté

    # On instancie un objet Avis en mémoire (sans le sauvegarder en base)
    # car la policy n'a besoin que de record.reviewed_user pour fonctionner
    @avis = Avis.new(
      reviewer:      @reviewer,
      reviewed_user: @reviewed_user,
      # Ces champs sont nécessaires pour que l'objet soit instanciable
      # mais on ne les sauvegarde pas (pas de validation déclenchée)
      rating:        5
    )
  end

  # ── create? ───────────────────────────────────────────────────────────────

  # Cas nominal : un utilisateur connecté peut noter quelqu'un d'autre
  def test_create_autorise_pour_user_connecte_et_reviewed_user_different
    assert AvisPolicy.new(@reviewer, @avis).create?,
           "Un utilisateur connecté doit pouvoir noter quelqu'un d'autre"
  end

  # Cas d'erreur : un utilisateur non connecté (nil) ne peut pas noter
  def test_create_interdit_pour_user_nil
    refute AvisPolicy.new(nil, @avis).create?,
           "Un utilisateur non connecté ne doit pas pouvoir noter"
  end

  # Cas d'erreur : on ne peut pas se noter soi-même
  def test_create_interdit_si_user_note_lui_meme
    # On crée un avis où reviewer == reviewed_user (auto-notation)
    avis_auto = Avis.new(
      reviewer:      @reviewer,
      reviewed_user: @reviewer,  # même utilisateur !
      rating:        5
    )
    refute AvisPolicy.new(@reviewer, avis_auto).create?,
           "Un utilisateur ne doit pas pouvoir se noter lui-même"
  end
end
