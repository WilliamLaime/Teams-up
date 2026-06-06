require "test_helper"

# Tests de TeamPolicy — vérifie qui peut faire quoi sur les équipes.
# Règle générale : seul le captain peut modifier/supprimer/transférer.
# Tout membre non-captain peut quitter. Tout user connecté peut voir et créer.
class TeamPolicyTest < ActiveSupport::TestCase
  def setup
    # Récupération des utilisateurs depuis les fixtures
    @captain = users(:one)  # captain de l'équipe :one
    @member  = users(:two)  # membre ordinaire de l'équipe :one (pas captain)

    # L'équipe de test dont @captain est le captain
    @team = teams(:one)
  end

  # ── index? ────────────────────────────────────────────────────────────────

  # Tout utilisateur connecté peut voir la liste des équipes
  # (le Scope filtre ensuite pour n'afficher que ses propres équipes)
  def test_index_pour_le_captain
    assert TeamPolicy.new(@captain, @team).index?,
           "Le captain doit pouvoir accéder à la liste des équipes"
  end

  # Un membre non-captain doit aussi pouvoir accéder à l'index
  def test_index_pour_un_membre
    assert TeamPolicy.new(@member, @team).index?,
           "Un membre non-captain doit pouvoir accéder à la liste des équipes"
  end

  # ── show? ─────────────────────────────────────────────────────────────────

  # Tout utilisateur connecté peut voir la page d'une équipe
  def test_show_pour_le_captain
    assert TeamPolicy.new(@captain, @team).show?,
           "Le captain doit pouvoir voir la page de son équipe"
  end

  # Un membre ordinaire peut aussi voir la page de l'équipe
  def test_show_pour_un_membre
    assert TeamPolicy.new(@member, @team).show?,
           "Un membre non-captain doit pouvoir voir la page de l'équipe"
  end

  # ── create? ───────────────────────────────────────────────────────────────

  # Tout utilisateur connecté peut créer une équipe
  def test_create_pour_le_captain
    assert TeamPolicy.new(@captain, @team).create?,
           "Le captain doit pouvoir créer une équipe"
  end

  # Un membre ordinaire peut aussi créer une équipe (tout user connecté peut)
  def test_create_pour_un_membre
    assert TeamPolicy.new(@member, @team).create?,
           "Un membre non-captain doit aussi pouvoir créer une équipe"
  end

  # ── update? ───────────────────────────────────────────────────────────────

  # Seul le captain peut modifier l'équipe
  def test_update_autorise_pour_le_captain
    assert TeamPolicy.new(@captain, @team).update?,
           "Le captain doit pouvoir modifier son équipe"
  end

  # Un membre ordinaire ne peut pas modifier l'équipe
  def test_update_interdit_pour_un_membre
    refute TeamPolicy.new(@member, @team).update?,
           "Un membre non-captain ne doit pas pouvoir modifier l'équipe"
  end

  # ── destroy? ──────────────────────────────────────────────────────────────

  # Seul le captain peut supprimer l'équipe
  def test_destroy_autorise_pour_le_captain
    assert TeamPolicy.new(@captain, @team).destroy?,
           "Le captain doit pouvoir supprimer son équipe"
  end

  # Un membre ordinaire ne peut pas supprimer l'équipe
  def test_destroy_interdit_pour_un_membre
    refute TeamPolicy.new(@member, @team).destroy?,
           "Un membre non-captain ne doit pas pouvoir supprimer l'équipe"
  end

  # ── transfer_captain? ────────────────────────────────────────────────────

  # Seul le captain peut transférer son rôle à un autre membre
  def test_transfer_captain_autorise_pour_le_captain
    assert TeamPolicy.new(@captain, @team).transfer_captain?,
           "Le captain doit pouvoir transférer son rôle"
  end

  # Un membre ordinaire ne peut pas transférer le capitanat
  def test_transfer_captain_interdit_pour_un_membre
    refute TeamPolicy.new(@member, @team).transfer_captain?,
           "Un membre non-captain ne doit pas pouvoir transférer le capitanat"
  end

  # ── leave? ────────────────────────────────────────────────────────────────

  # Un membre non-captain peut quitter l'équipe
  def test_leave_autorise_pour_un_membre
    assert TeamPolicy.new(@member, @team).leave?,
           "Un membre non-captain doit pouvoir quitter l'équipe"
  end

  # Le captain ne peut pas quitter son équipe (il faut d'abord transférer)
  def test_leave_interdit_pour_le_captain
    refute TeamPolicy.new(@captain, @team).leave?,
           "Le captain ne doit pas pouvoir quitter son équipe directement"
  end

  # Un utilisateur qui n'est pas membre du tout ne peut pas non plus quitter.
  # On utilise create_test_user (test_helper.rb) plutôt que User.create! direct
  # car first_name et last_name sont obligatoires (validés on: :create).
  def test_leave_interdit_pour_un_non_membre
    stranger = create_test_user(
      email:      "stranger@example.com",
      first_name: "Stranger",
      last_name:  "Test"
    )
    refute TeamPolicy.new(stranger, @team).leave?,
           "Un utilisateur non-membre ne doit pas pouvoir quitter l'équipe"
  ensure
    # Nettoyage : on supprime le user créé pour ce test uniquement
    # destroy passe par les callbacks et supprime aussi le Profil associé
    stranger&.destroy
  end

  # ── Scope#resolve ────────────────────────────────────────────────────────

  # Le scope retourne uniquement les équipes dont l'user est membre
  def test_scope_retourne_les_equipes_du_captain
    resolved = TeamPolicy::Scope.new(@captain, Team.all).resolve
    # @captain est membre de l'équipe :one → doit apparaître
    assert_includes resolved, @team,
                    "Le scope doit inclure l'équipe dont l'user est captain/membre"
  end

  # Un membre non-captain voit aussi les équipes dont il fait partie
  def test_scope_retourne_les_equipes_du_membre
    resolved = TeamPolicy::Scope.new(@member, Team.all).resolve
    assert_includes resolved, @team,
                    "Le scope doit inclure l'équipe dont l'user est membre"
  end

  # Si l'utilisateur est nil (non connecté), le scope retourne une collection vide
  def test_scope_vide_pour_utilisateur_nil
    resolved = TeamPolicy::Scope.new(nil, Team.all).resolve
    assert_equal 0, resolved.count,
                 "Le scope doit être vide pour un utilisateur non connecté"
  end
end
