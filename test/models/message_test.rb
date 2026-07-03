require "test_helper"

# Tests du modèle Message.
# Un Message appartient à un User et à l'une de ces trois cibles :
#   - un Match (chat de groupe du match)
#   - une PrivateConversation (chat 1-to-1)
#   - une Team (chat d'équipe)
# Règles :
#   - Le contenu est obligatoire et limité à 1000 caractères
#   - Un message doit appartenir à au moins une des trois cibles ci-dessus
class MessageTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée un utilisateur de base pour les tests
  def create_user(email: "msg_user@example.com")
    create_test_user(email: email, first_name: "Msg", last_name: "User")
  end

  # Crée un match minimal valide pour attacher un message
  def create_match(user:)
    sport = Sport.create!(name: "Football Test", slug: "football_test", icon: "⚽")
    Match.create!(
      title:        "Match Test",
      place:        "Terrain Test",
      date:         Date.tomorrow,
      time:         1.hour.from_now, # doit être au moins 30min dans le futur
      players_needed:  10,
      level:        "Tout niveau",   # champ obligatoire (validates :level, presence: true)
      user:         user,
      sport:        sport
    )
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS — contenu
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un message avec contenu attaché à un match est valide
  def test_message_valide_avec_contenu_et_match
    user  = create_user
    match = create_match(user: user)
    msg   = Message.new(user: user, match: match, content: "Bonjour l'équipe !")
    assert msg.valid?, "Un message valide attaché à un match doit passer les validations"
  end

  # Cas d'erreur : le contenu est obligatoire
  def test_message_invalide_sans_contenu
    user  = create_user
    match = create_match(user: user)
    msg   = Message.new(user: user, match: match, content: nil)
    refute msg.valid?, "Un message sans contenu doit être invalide"
    assert_includes msg.errors[:content], "ne peut pas être vide"
  end

  # Cas d'erreur : le contenu ne peut pas dépasser 1000 caractères
  def test_message_invalide_si_contenu_trop_long
    user    = create_user
    match   = create_match(user: user)
    # 1001 caractères → dépasse la limite
    trop_long = "A" * 1001
    msg = Message.new(user: user, match: match, content: trop_long)
    refute msg.valid?, "Un message de plus de 1000 caractères doit être invalide"
    assert_includes msg.errors[:content], "est trop long (maximum 1000 caractères)"
  end

  # Edge case : exactement 1000 caractères → valide
  def test_message_valide_avec_contenu_de_1000_caracteres
    user    = create_user
    match   = create_match(user: user)
    limite  = "A" * 1000
    msg = Message.new(user: user, match: match, content: limite)
    assert msg.valid?, "Un message de 1000 caractères exactement doit être valide"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATION — appartenance obligatoire à une cible
  # ════════════════════════════════════════════════════════════════════════════

  # Cas d'erreur : un message sans match, ni private_conversation, ni team est invalide
  def test_message_invalide_sans_aucune_cible
    user = create_user
    msg  = Message.new(user: user, content: "Message orphelin")
    # match_id, private_conversation_id et team_id sont tous nil → invalide
    refute msg.valid?, "Un message sans aucune cible (match/conv/team) doit être invalide"
    assert msg.errors[:base].any? { |e| e.include?("doit appartenir") },
           "L'erreur doit mentionner l'obligation d'appartenir à une cible"
  end

  # Cas nominal : un message attaché à un match est valide
  def test_message_valide_attache_a_un_match
    user  = create_user
    match = create_match(user: user)
    msg   = Message.new(user: user, match: match, content: "Présent !")
    assert msg.valid?, "Un message attaché à un match doit être valide"
  end

  # Cas nominal : un message attaché à une équipe est valide
  def test_message_valide_attache_a_une_equipe
    captain = create_user(email: "captain_msg@example.com")
    team    = Team.create!(name: "Team Chat", captain: captain)
    msg     = Message.new(user: captain, team: team, content: "Bonjour l'équipe !")
    assert msg.valid?, "Un message attaché à une équipe doit être valide"
  end
end
