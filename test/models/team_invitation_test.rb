require "test_helper"

# Tests du modèle TeamInvitation.
# Une TeamInvitation représente une invitation à rejoindre une équipe.
# Statuts possibles : "pending", "accepted", "refused", "proposed"
# Règles :
#   - Un user ne peut avoir qu'une seule invitation pending par équipe
#   - Un user ne peut avoir qu'une seule proposition (proposed) par équipe
class TeamInvitationTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée les données de base : captain, invité et équipe
  def setup_data
    captain = create_test_user(email: "captain@example.com", first_name: "Cap", last_name: "Tain")
    invitee = create_test_user(email: "invitee@example.com", first_name: "Inv", last_name: "Itee")
    team    = Team.create!(name: "Les Testeurs", captain: captain)
    [captain, invitee, team]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une invitation avec un statut valide est acceptée
  def test_invitation_valide_avec_statut_pending
    captain, invitee, team = setup_data
    invitation = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "pending")
    assert invitation.valid?, "Une invitation pending doit être valide : #{invitation.errors.full_messages}"
  end

  # Cas d'erreur : un statut inconnu est rejeté
  def test_invitation_invalide_avec_statut_inconnu
    captain, invitee, team = setup_data
    invitation = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "unknown")
    refute invitation.valid?, "Un statut inconnu doit invalider l'invitation"
    # La traduction du message "inclusion" n'est pas définie en fr → on vérifie la présence d'erreur
    assert invitation.errors[:status].any?, "Une erreur sur :status doit être présente pour un statut inconnu"
  end

  # Cas d'erreur : deux invitations pending pour le même user dans la même équipe
  def test_unicite_invitation_pending_par_equipe
    captain, invitee, team = setup_data
    TeamInvitation.create!(team: team, inviter: captain, invitee: invitee, status: "pending")
    doublon = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "pending")
    refute doublon.valid?, "On ne peut pas créer deux invitations pending pour le même user dans la même équipe"
    assert_includes doublon.errors[:invitee_id], "a déjà une invitation en attente pour cette équipe"
  end

  # Edge case : une invitation "accepted" peut coexister avec une nouvelle "pending"
  # (cas rare mais techniquement possible selon le schéma)
  def test_invitation_pending_valide_si_precedente_etait_refused
    captain, invitee, team = setup_data
    # Crée une première invitation refusée
    TeamInvitation.create!(team: team, inviter: captain, invitee: invitee, status: "refused")
    # Une nouvelle invitation pending pour le même user doit être valide
    nouvelle = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "pending")
    assert nouvelle.valid?, "Une nouvelle invitation pending est valide si la précédente était refusée"
  end

  # Cas d'erreur : deux propositions (proposed) pour le même user dans la même équipe
  def test_unicite_proposition_par_equipe
    captain, invitee, team = setup_data
    proposer = create_test_user(email: "proposer@example.com", first_name: "Pro", last_name: "Poser")
    team.team_members.create!(user: proposer, role: "member", joined_at: Time.current)
    TeamInvitation.create!(team: team, inviter: captain, invitee: invitee, proposed_by: proposer, status: "proposed")
    doublon = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, proposed_by: proposer, status: "proposed")
    refute doublon.valid?, "On ne peut pas créer deux propositions pour le même user dans la même équipe"
  end

  # Chaque statut valide doit être accepté par la validation d'inclusion
  def test_tous_les_statuts_valides_sont_acceptes
    captain, invitee, team = setup_data
    TeamInvitation::STATUSES.each do |statut|
      inv = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: statut)
      assert inv.valid?, "Le statut '#{statut}' doit être considéré valide"
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # METHODES D'INSTANCE
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : pending? retourne true pour une invitation en attente
  def test_pending_retourne_true
    captain, invitee, team = setup_data
    inv = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "pending")
    assert inv.pending?, "pending? doit retourner true quand status == 'pending'"
  end

  # Cas nominal : accepted? retourne true pour une invitation acceptée
  def test_accepted_retourne_true
    captain, invitee, team = setup_data
    inv = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "accepted")
    assert inv.accepted?, "accepted? doit retourner true quand status == 'accepted'"
  end

  # Cas nominal : refused? retourne true pour une invitation refusée
  def test_refused_retourne_true
    captain, invitee, team = setup_data
    inv = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "refused")
    assert inv.refused?, "refused? doit retourner true quand status == 'refused'"
  end

  # Cas nominal : proposed? retourne true pour une proposition
  def test_proposed_retourne_true
    captain, invitee, team = setup_data
    proposer = create_test_user(email: "pro@example.com", first_name: "Pro", last_name: "User")
    inv = TeamInvitation.new(
      team:        team,
      inviter:     captain,
      invitee:     invitee,
      proposed_by: proposer,
      status:      "proposed"
    )
    assert inv.proposed?, "proposed? doit retourner true quand status == 'proposed'"
  end

  # Cas d'erreur : pending? retourne false pour un autre statut
  def test_pending_retourne_false_si_accepted
    captain, invitee, team = setup_data
    inv = TeamInvitation.new(team: team, inviter: captain, invitee: invitee, status: "accepted")
    refute inv.pending?, "pending? doit retourner false quand status != 'pending'"
  end
end
