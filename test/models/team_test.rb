require "test_helper"

# Tests du modèle Team.
# Ce modèle représente une équipe sportive. Il appartient à un captain (User),
# a des membres (TeamMember), des invitations (TeamInvitation) et des matchs.
# Règles importantes :
#   - Le nom est obligatoire et limité à 50 caractères
#   - Un captain ne peut pas avoir deux équipes du même nom
#   - Le captain est automatiquement ajouté comme TeamMember à la création
#   - Le SVG du blason est sanitisé pour supprimer les balises <script>
class TeamTest < ActiveSupport::TestCase
  # Nettoyage complet après chaque test pour éviter les FK violations PostgreSQL
  teardown { teardown_db }

  # ─── Helpers privés ────────────────────────────────────────────────────────

  # Crée une équipe valide et l'enregistre en base.
  # On utilise create_test_user (défini dans test_helper) pour avoir User + Profil.
  def create_team(name: "Les Warriors", captain: nil)
    captain ||= create_test_user(email: "captain@example.com", first_name: "Cap", last_name: "Tain")
    Team.create!(name: name, captain: captain)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une équipe avec un nom valide doit être persistée sans erreur
  def test_equipe_valide_avec_nom
    captain = create_test_user(email: "cap@example.com", first_name: "Cap", last_name: "Tain")
    team    = Team.new(name: "Les Eagles", captain: captain)
    # assert valid? vérifie qu'aucune validation ne bloque l'enregistrement
    assert team.valid?, "Une équipe avec un nom valide doit être valide : #{team.errors.full_messages}"
  end

  # Cas d'erreur : le nom est obligatoire
  def test_equipe_invalide_sans_nom
    captain = create_test_user(email: "cap2@example.com", first_name: "Cap", last_name: "Deux")
    team    = Team.new(name: nil, captain: captain)
    # refute valid? vérifie qu'au moins une erreur est présente
    refute team.valid?, "Une équipe sans nom doit être invalide"
    # L'app est en français → message traduit ("ne peut pas être vide")
    assert_includes team.errors[:name], "ne peut pas être vide"
  end

  # Cas d'erreur : le nom ne peut pas dépasser 50 caractères
  def test_equipe_invalide_si_nom_trop_long
    captain   = create_test_user(email: "cap3@example.com", first_name: "Cap", last_name: "Trois")
    long_name = "A" * 51 # 51 caractères → dépasse la limite de 50
    team      = Team.new(name: long_name, captain: captain)
    refute team.valid?, "Un nom de plus de 50 caractères doit rendre l'équipe invalide"
    assert_includes team.errors[:name], "est trop long (maximum 50 caractères)"
  end

  # Edge case : exactement 50 caractères → valide
  def test_equipe_valide_avec_nom_de_50_caracteres
    captain   = create_test_user(email: "cap4@example.com", first_name: "Cap", last_name: "Quatre")
    name_50   = "A" * 50
    team      = Team.new(name: name_50, captain: captain)
    assert team.valid?, "Un nom de 50 caractères exactement doit être valide"
  end

  # Cas d'erreur : un même captain ne peut pas avoir deux équipes du même nom
  def test_equipe_invalide_si_doublon_nom_pour_meme_captain
    captain = create_test_user(email: "cap5@example.com", first_name: "Cap", last_name: "Cinq")
    Team.create!(name: "Les Rockets", captain: captain)
    doublon = Team.new(name: "Les Rockets", captain: captain)
    refute doublon.valid?, "Un captain ne peut pas avoir deux équipes avec le même nom"
    assert_includes doublon.errors[:name], "Vous avez déjà une équipe avec ce nom"
  end

  # Edge case : deux capitaines différents PEUVENT avoir des équipes du même nom
  def test_deux_capitaines_differents_peuvent_avoir_le_meme_nom
    cap_a = create_test_user(email: "capa@example.com", first_name: "Cap", last_name: "A")
    cap_b = create_test_user(email: "capb@example.com", first_name: "Cap", last_name: "B")
    Team.create!(name: "Les Invincibles", captain: cap_a)
    equipe_b = Team.new(name: "Les Invincibles", captain: cap_b)
    assert equipe_b.valid?, "Deux captains différents peuvent avoir des équipes du même nom"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # CALLBACK : add_captain_as_member
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : après la création, le captain doit être automatiquement TeamMember
  def test_captain_ajoute_comme_membre_apres_creation
    captain = create_test_user(email: "cap6@example.com", first_name: "Cap", last_name: "Six")
    team    = Team.create!(name: "Callback Team", captain: captain)
    # Vérifie que le TeamMember avec le rôle "captain" a bien été créé
    assert team.team_members.exists?(user: captain, role: "captain"),
           "Le captain doit être automatiquement ajouté comme TeamMember après création"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES D'INSTANCE
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : captain?(user) retourne true si l'user est le captain
  def test_captain_retourne_true_pour_le_captain
    captain = create_test_user(email: "cap7@example.com", first_name: "Cap", last_name: "Sept")
    team    = Team.create!(name: "Team Captain Test", captain: captain)
    assert team.captain?(captain), "captain? doit retourner true pour le captain de l'équipe"
  end

  # Cas d'erreur : captain?(user) retourne false pour un autre utilisateur
  def test_captain_retourne_false_pour_un_non_captain
    captain  = create_test_user(email: "cap8@example.com", first_name: "Cap", last_name: "Huit")
    other    = create_test_user(email: "other@example.com", first_name: "Other", last_name: "User")
    team     = Team.create!(name: "Team Non-Captain", captain: captain)
    refute team.captain?(other), "captain? doit retourner false pour un non-captain"
  end

  # Cas nominal : member?(user) retourne true pour le captain (qui est aussi membre)
  def test_member_retourne_true_pour_le_captain
    captain = create_test_user(email: "cap9@example.com", first_name: "Cap", last_name: "Neuf")
    team    = Team.create!(name: "Team Member Test", captain: captain)
    assert team.member?(captain), "member? doit retourner true pour le captain (il est aussi membre)"
  end

  # Cas nominal : member?(user) retourne true pour un membre ordinaire
  def test_member_retourne_true_pour_un_membre_ordinaire
    captain = create_test_user(email: "cap10@example.com", first_name: "Cap", last_name: "Dix")
    member  = create_test_user(email: "member@example.com", first_name: "Mem", last_name: "Ber")
    team    = Team.create!(name: "Team Avec Membre", captain: captain)
    # Ajoute le membre manuellement via TeamMember
    team.team_members.create!(user: member, role: "member", joined_at: Time.current)
    assert team.member?(member), "member? doit retourner true pour un membre ordinaire"
  end

  # Cas d'erreur : member?(user) retourne false pour quelqu'un hors de l'équipe
  def test_member_retourne_false_pour_un_outsider
    captain  = create_test_user(email: "cap11@example.com", first_name: "Cap", last_name: "Onze")
    outsider = create_test_user(email: "outsider@example.com", first_name: "Out", last_name: "Sider")
    team     = Team.create!(name: "Team Outsider Test", captain: captain)
    refute team.member?(outsider), "member? doit retourner false pour quelqu'un hors de l'équipe"
  end

  # Cas nominal : invitation_pending_for? retourne true si une invitation pending existe
  def test_invitation_pending_for_retourne_true_si_invitation_pending
    captain = create_test_user(email: "cap12@example.com", first_name: "Cap", last_name: "Douze")
    invitee = create_test_user(email: "invitee@example.com", first_name: "Inv", last_name: "Itee")
    team    = Team.create!(name: "Team Invitation Test", captain: captain)
    # Crée une invitation avec le statut "pending"
    team.team_invitations.create!(inviter: captain, invitee: invitee, status: "pending")
    assert team.invitation_pending_for?(invitee),
           "invitation_pending_for? doit retourner true si une invitation pending existe"
  end

  # Cas d'erreur : invitation_pending_for? retourne false si pas d'invitation pending
  def test_invitation_pending_for_retourne_false_si_pas_invitation
    captain = create_test_user(email: "cap13@example.com", first_name: "Cap", last_name: "Treize")
    invitee = create_test_user(email: "invitee2@example.com", first_name: "Inv", last_name: "Deux")
    team    = Team.create!(name: "Team Sans Invitation", captain: captain)
    refute team.invitation_pending_for?(invitee),
           "invitation_pending_for? doit retourner false si aucune invitation pending"
  end

  # Edge case : invitation_pending_for? retourne false si l'invitation est "accepted"
  def test_invitation_pending_for_retourne_false_si_invitation_acceptee
    captain = create_test_user(email: "cap14@example.com", first_name: "Cap", last_name: "Quatorze")
    invitee = create_test_user(email: "invitee3@example.com", first_name: "Inv", last_name: "Trois")
    team    = Team.create!(name: "Team Invite Acceptee", captain: captain)
    # Invitation déjà acceptée → ne doit pas compter comme "pending"
    team.team_invitations.create!(inviter: captain, invitee: invitee, status: "accepted")
    refute team.invitation_pending_for?(invitee),
           "invitation_pending_for? doit retourner false si l'invitation est déjà acceptée"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # CALLBACK : sanitize_badge_svg
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un SVG sans script est conservé intact (les balises valides restent)
  def test_sanitize_badge_svg_conserve_les_balises_valides
    captain = create_test_user(email: "cap15@example.com", first_name: "Cap", last_name: "Quinze")
    team    = Team.create!(name: "Team SVG Safe", captain: captain)
    svg_propre = '<svg xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="40"/></svg>'
    team.update!(badge_svg: svg_propre)
    # Le SVG sans script doit passer la sanitisation sans modification majeure
    assert_includes team.reload.badge_svg, "<circle", "Les balises SVG valides doivent être conservées"
  end

  # Cas d'erreur de sécurité : les balises <script> doivent être supprimées
  def test_sanitize_badge_svg_supprime_les_scripts
    captain  = create_test_user(email: "cap16@example.com", first_name: "Cap", last_name: "Seize")
    team     = Team.create!(name: "Team SVG Malicious", captain: captain)
    svg_xss  = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert("xss")</script><circle cx="50" cy="50" r="40"/></svg>'
    team.update!(badge_svg: svg_xss)
    # La balise <script> doit avoir été supprimée par la sanitisation
    assert_not_includes team.reload.badge_svg, "<script",
                        "La balise <script> doit être supprimée du SVG pour éviter l'injection XSS"
  end
end
