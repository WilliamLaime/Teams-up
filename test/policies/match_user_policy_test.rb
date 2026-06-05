require "test_helper"

# Tests de MatchUserPolicy — vérifie les autorisations sur les inscriptions à un match.
#
# Règles testées :
#   create?  → tout utilisateur connecté peut rejoindre un match
#   destroy? → uniquement l'inscrit concerné peut se désinscrire
#   approve? → uniquement l'organisateur du match (role "organisateur")
#   reject?  → même logique que approve?
#   confirm? → uniquement l'inscrit concerné peut confirmer sa place
class MatchUserPolicyTest < ActiveSupport::TestCase
  def setup
    @organisateur = users(:one)  # créateur du match, role "organisateur" dans match_users
    @joueur       = users(:two)  # joueur ordinaire inscrit au match

    # Les inscriptions au match issues des fixtures
    # match_users(:organisateur_one) → user :one, role "organisateur"
    # match_users(:joueur_two)       → user :two, role "joueur"
    @match_user_organisateur = match_users(:organisateur_one)
    @match_user_joueur       = match_users(:joueur_two)
  end

  # ── create? ───────────────────────────────────────────────────────────────

  # Cas nominal : tout utilisateur connecté peut s'inscrire à un match
  def test_create_autorise_pour_l_organisateur
    assert MatchUserPolicy.new(@organisateur, @match_user_organisateur).create?,
           "L'organisateur doit pouvoir s'inscrire (create? retourne toujours true)"
  end

  # Un joueur ordinaire peut aussi s'inscrire
  def test_create_autorise_pour_un_joueur
    assert MatchUserPolicy.new(@joueur, @match_user_joueur).create?,
           "Un joueur doit pouvoir s'inscrire à un match"
  end

  # ── destroy? ──────────────────────────────────────────────────────────────

  # Un joueur peut se désinscrire de sa propre inscription
  def test_destroy_autorise_pour_le_joueur_concerne
    # @joueur est bien record.user de @match_user_joueur
    assert MatchUserPolicy.new(@joueur, @match_user_joueur).destroy?,
           "Un joueur doit pouvoir se désinscrire de sa propre inscription"
  end

  # Un autre utilisateur ne peut pas supprimer l'inscription de quelqu'un d'autre
  def test_destroy_interdit_pour_un_autre_utilisateur
    # @organisateur essaie de supprimer l'inscription de @joueur → interdit
    refute MatchUserPolicy.new(@organisateur, @match_user_joueur).destroy?,
           "Un autre utilisateur ne doit pas pouvoir supprimer une inscription qui ne lui appartient pas"
  end

  # ── approve? ──────────────────────────────────────────────────────────────

  # L'organisateur du match peut approuver un joueur en attente
  def test_approve_autorise_pour_l_organisateur
    # On passe @match_user_joueur comme record : c'est le joueur à approuver
    # L'organisateur est @organisateur, qui a bien role "organisateur" dans match_users
    assert MatchUserPolicy.new(@organisateur, @match_user_joueur).approve?,
           "L'organisateur doit pouvoir approuver un joueur en attente"
  end

  # Un joueur ordinaire ne peut pas approuver d'autres joueurs
  def test_approve_interdit_pour_un_joueur_lambda
    # @joueur essaie d'approuver l'inscription de l'organisateur → interdit
    refute MatchUserPolicy.new(@joueur, @match_user_organisateur).approve?,
           "Un joueur ordinaire ne doit pas pouvoir approuver d'autres joueurs"
  end

  # ── reject? ───────────────────────────────────────────────────────────────

  # L'organisateur peut rejeter un joueur (même logique que approve?)
  def test_reject_autorise_pour_l_organisateur
    assert MatchUserPolicy.new(@organisateur, @match_user_joueur).reject?,
           "L'organisateur doit pouvoir rejeter un joueur"
  end

  # Un joueur ordinaire ne peut pas rejeter d'autres joueurs
  def test_reject_interdit_pour_un_joueur_lambda
    refute MatchUserPolicy.new(@joueur, @match_user_organisateur).reject?,
           "Un joueur ordinaire ne doit pas pouvoir rejeter d'autres joueurs"
  end

  # ── confirm? ──────────────────────────────────────────────────────────────

  # Le joueur concerné peut confirmer sa propre place
  def test_confirm_autorise_pour_le_joueur_concerne
    assert MatchUserPolicy.new(@joueur, @match_user_joueur).confirm?,
           "Un joueur doit pouvoir confirmer sa propre place"
  end

  # Un autre utilisateur ne peut pas confirmer la place de quelqu'un d'autre
  def test_confirm_interdit_pour_un_autre_utilisateur
    # @organisateur essaie de confirmer la place de @joueur → interdit
    refute MatchUserPolicy.new(@organisateur, @match_user_joueur).confirm?,
           "Un utilisateur ne doit pas pouvoir confirmer la place d'un autre"
  end
end
