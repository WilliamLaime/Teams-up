require "test_helper"

# Tests du modèle TeamMember.
# Un TeamMember est la table de jointure entre un User et une Team.
# Il a un rôle : "captain" ou "member".
# Règles :
#   - Le rôle doit être dans ROLES = ["captain", "member"]
#   - Un user ne peut pas être membre deux fois dans la même équipe
class TeamMemberTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Prépare les données de base pour les tests
  def setup_data
    captain = create_test_user(email: "captain@example.com", first_name: "Cap", last_name: "Tain")
    member  = create_test_user(email: "member@example.com",  first_name: "Mem", last_name: "Ber")
    # Le callback add_captain_as_member crée automatiquement le TeamMember du captain
    team = Team.create!(name: "Les Testeurs", captain: captain)
    [captain, member, team]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un TeamMember avec le rôle "member" est valide
  def test_team_member_valide_avec_role_member
    captain, member, team = setup_data
    tm = TeamMember.new(team: team, user: member, role: "member", joined_at: Time.current)
    assert tm.valid?, "Un TeamMember avec rôle 'member' doit être valide"
  end

  # Cas nominal : un TeamMember avec le rôle "captain" est valide
  def test_team_member_valide_avec_role_captain
    # On crée un user et une équipe séparée pour tester le rôle captain
    user_cap = create_test_user(email: "cap2@example.com", first_name: "Cap2", last_name: "Test")
    team2    = Team.create!(name: "Team Captain Role", captain: user_cap)
    # Le callback a déjà créé le TeamMember pour user_cap → on vérifie directement
    tm = TeamMember.find_by(team: team2, user: user_cap)
    assert_equal "captain", tm.role, "Le callback doit créer le captain avec le rôle 'captain'"
  end

  # Cas d'erreur : un rôle inconnu doit invalider le TeamMember
  def test_team_member_invalide_avec_role_inconnu
    captain, member, team = setup_data
    tm = TeamMember.new(team: team, user: member, role: "admin", joined_at: Time.current)
    refute tm.valid?, "Un rôle inconnu ('admin') doit invalider le TeamMember"
    # La traduction du message "inclusion" n'est pas définie en fr → on vérifie la présence d'erreur
    assert tm.errors[:role].any?, "Une erreur sur :role doit être présente pour un rôle inconnu"
  end

  # Cas d'erreur : un user ne peut pas être membre deux fois dans la même équipe
  def test_unicite_user_par_equipe
    captain, member, team = setup_data
    # Ajoute member une première fois
    TeamMember.create!(team: team, user: member, role: "member", joined_at: Time.current)
    # Essaie de l'ajouter une deuxième fois dans la même équipe
    doublon = TeamMember.new(team: team, user: member, role: "member", joined_at: Time.current)
    refute doublon.valid?, "Un user ne peut pas être membre deux fois dans la même équipe"
    # Ce message est défini directement dans le modèle → pas de traduction i18n
    assert doublon.errors[:user_id].any? { |e| e.include?("membre") },
           "L'erreur doit mentionner que l'utilisateur est déjà membre"
  end

  # Edge case : le même user peut être membre de deux équipes différentes
  def test_user_peut_etre_membre_de_deux_equipes_differentes
    captain, member, team = setup_data
    cap2  = create_test_user(email: "cap3@example.com", first_name: "Cap", last_name: "Trois")
    team2 = Team.create!(name: "Team Deux", captain: cap2)
    # Ajoute member dans team2 → doit être valide même si déjà dans team
    TeamMember.create!(team: team, user: member, role: "member", joined_at: Time.current)
    tm2 = TeamMember.new(team: team2, user: member, role: "member", joined_at: Time.current)
    assert tm2.valid?, "Un user peut être membre de plusieurs équipes différentes"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES D'INSTANCE
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : captain? retourne true quand le rôle est "captain"
  def test_captain_retourne_true_pour_role_captain
    captain, _member, team = setup_data
    # Le callback a créé un TeamMember avec role "captain" pour le captain
    tm = TeamMember.find_by(team: team, user: captain)
    assert tm.captain?, "captain? doit retourner true quand role == 'captain'"
  end

  # Cas d'erreur : captain? retourne false quand le rôle est "member"
  def test_captain_retourne_false_pour_role_member
    captain, member, team = setup_data
    tm = TeamMember.create!(team: team, user: member, role: "member", joined_at: Time.current)
    refute tm.captain?, "captain? doit retourner false quand role == 'member'"
  end

  # Cas nominal : member? retourne true quand le rôle est "member"
  def test_member_retourne_true_pour_role_member
    captain, member, team = setup_data
    tm = TeamMember.create!(team: team, user: member, role: "member", joined_at: Time.current)
    assert tm.member?, "member? doit retourner true quand role == 'member'"
  end

  # Cas d'erreur : member? retourne false quand le rôle est "captain"
  def test_member_retourne_false_pour_role_captain
    captain, _member, team = setup_data
    tm = TeamMember.find_by(team: team, user: captain)
    refute tm.member?, "member? doit retourner false quand role == 'captain'"
  end
end
