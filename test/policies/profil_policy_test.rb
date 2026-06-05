require "test_helper"

# Tests de ProfilPolicy — vérifie que seul le propriétaire d'un profil peut
# le voir (dans les vues protégées) et le modifier.
#
# Attention : dans l'app, certaines vues de profil sont publiques (show_simple,
# show_user_simple). La policy ProfilPolicy#show? protège uniquement les vues
# qui nécessitent d'être le propriétaire (ex: /profil — son propre profil).
#
# Règles testées :
#   show?   → uniquement le propriétaire du profil
#   update? → uniquement le propriétaire du profil
class ProfilPolicyTest < ActiveSupport::TestCase
  def setup
    @owner = users(:one)  # propriétaire du profil
    @other = users(:two)  # autre utilisateur (pas propriétaire)

    # Le profil appartenant à @owner
    @profil = profils(:one)
  end

  # ── show? ─────────────────────────────────────────────────────────────────

  # Le propriétaire peut voir son propre profil (vue protégée)
  def test_show_autorise_pour_le_proprietaire
    assert ProfilPolicy.new(@owner, @profil).show?,
           "Le propriétaire doit pouvoir voir son propre profil"
  end

  # Un autre utilisateur ne peut pas accéder à la vue protégée du profil d'autrui
  def test_show_interdit_pour_un_autre_utilisateur
    refute ProfilPolicy.new(@other, @profil).show?,
           "Un autre utilisateur ne doit pas pouvoir voir le profil protégé d'autrui"
  end

  # ── update? ───────────────────────────────────────────────────────────────

  # Le propriétaire peut modifier son propre profil
  def test_update_autorise_pour_le_proprietaire
    assert ProfilPolicy.new(@owner, @profil).update?,
           "Le propriétaire doit pouvoir modifier son propre profil"
  end

  # Un autre utilisateur ne peut pas modifier le profil de quelqu'un d'autre
  def test_update_interdit_pour_un_autre_utilisateur
    refute ProfilPolicy.new(@other, @profil).update?,
           "Un autre utilisateur ne doit pas pouvoir modifier le profil d'autrui"
  end

  # ── edit? (alias de update?) ──────────────────────────────────────────────
  # edit? est défini dans ApplicationPolicy comme un alias de update?
  # On vérifie que le comportement est cohérent

  def test_edit_autorise_pour_le_proprietaire
    assert ProfilPolicy.new(@owner, @profil).edit?,
           "edit? doit se comporter comme update? pour le propriétaire"
  end

  def test_edit_interdit_pour_un_autre_utilisateur
    refute ProfilPolicy.new(@other, @profil).edit?,
           "edit? doit se comporter comme update? pour un non-propriétaire"
  end
end
