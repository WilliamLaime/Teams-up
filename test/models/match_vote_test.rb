require "test_helper"

# Tests du modèle MatchVote.
# Un MatchVote représente le vote d'un joueur pour l'homme du match.
# Règles :
#   - Un joueur ne peut voter qu'une seule fois par match (unicité voter/match)
#   - On ne peut pas voter pour soi-même
#   - Les deux joueurs (voter et voted_for) doivent avoir participé (status: approved)
#   - Le match doit être terminé ET dans la fenêtre de 7 jours
class MatchVoteTest < ActiveSupport::TestCase
  teardown { teardown_db }

  # Crée un match terminé il y a 2 heures (dans la fenêtre de 7j).
  # On utilise save(validate: false) car le modèle Match interdit la création
  # d'un match dans le passé (validates :match_must_be_at_least_30min_in_future).
  # Ici on veut tester les votes, pas la validation de création du match.
  def create_completed_match(user:)
    sport = Sport.create!(name: "Football Vote", slug: "football_vote_test", icon: "⚽")
    match = Match.new(
      title:       "Match Vote Test",
      place:       "Terrain",
      date:        2.hours.ago.to_date,
      time:        2.hours.ago,
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        user,
      sport:       sport
    )
    # Bypass la validation de date pour simuler un match déjà terminé
    match.save(validate: false)
    match
  end

  # Crée un match terminé il y a plus de 7 jours (hors fenêtre).
  # Même approche : save(validate: false) pour bypasser la contrainte de date.
  def create_old_match(user:)
    sport = Sport.create!(name: "Football Old Vote", slug: "football_old_vote_test", icon: "⚽")
    match = Match.new(
      title:       "Vieux Match Vote",
      place:       "Terrain",
      date:        8.days.ago.to_date,
      time:        8.days.ago,
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        user,
      sport:       sport
    )
    match.save(validate: false)
    match
  end

  # Inscrit deux utilisateurs comme joueurs approuvés dans le match
  def add_approved_players(match:, voter:, voted_for:)
    MatchUser.create!(user: voter,     match: match, status: "approved", role: "joueur")
    MatchUser.create!(user: voted_for, match: match, status: "approved", role: "joueur")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un vote valide (match terminé dans la fenêtre, deux joueurs inscrits)
  def test_vote_valide
    voter     = create_test_user(email: "voter1@example.com", first_name: "Voter", last_name: "Un")
    voted_for = create_test_user(email: "voted1@example.com", first_name: "Voted", last_name: "Un")
    match     = create_completed_match(user: voter)
    add_approved_players(match: match, voter: voter, voted_for: voted_for)

    vote = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    assert vote.valid?, "Un vote valide doit passer les validations : #{vote.errors.full_messages}"
  end

  # Cas d'erreur : un joueur ne peut pas voter deux fois dans le même match
  def test_vote_invalide_si_voter_a_deja_vote
    voter     = create_test_user(email: "voter2@example.com", first_name: "Voter", last_name: "Deux")
    voted_for = create_test_user(email: "voted2@example.com", first_name: "Voted", last_name: "Deux")
    match     = create_completed_match(user: voter)
    add_approved_players(match: match, voter: voter, voted_for: voted_for)

    # Premier vote → valide
    MatchVote.create!(voter: voter, voted_for: voted_for, match: match)
    # Deuxième vote → invalide (unicité voter/match)
    doublon = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    refute doublon.valid?, "Un joueur ne peut pas voter deux fois dans le même match"
    assert doublon.errors[:voter_id].any?, "Une erreur d'unicité sur :voter_id doit être présente"
  end

  # Cas d'erreur : on ne peut pas voter pour soi-même
  def test_cannot_vote_for_yourself
    user  = create_test_user(email: "selfvote@example.com", first_name: "Self", last_name: "Vote")
    match = create_completed_match(user: user)
    MatchUser.create!(user: user, match: match, status: "approved", role: "joueur")

    vote = MatchVote.new(voter: user, voted_for: user, match: match)
    refute vote.valid?, "On ne peut pas voter pour soi-même"
    assert vote.errors[:base].any? { |e| e.include?("vous-même") },
           "L'erreur doit mentionner l'interdiction de voter pour soi-même"
  end

  # Cas d'erreur : le votant n'a pas participé au match
  def test_voter_doit_avoir_joue
    voter     = create_test_user(email: "voter3@example.com", first_name: "Voter", last_name: "Trois")
    voted_for = create_test_user(email: "voted3@example.com", first_name: "Voted", last_name: "Trois")
    match     = create_completed_match(user: voter)
    # Seul voted_for est inscrit comme approved
    MatchUser.create!(user: voted_for, match: match, status: "approved", role: "joueur")

    vote = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    refute vote.valid?, "On ne peut pas voter si on n'a pas participé au match"
    assert vote.errors[:base].any? { |e| e.include?("participé") }
  end

  # Cas d'erreur : le candidat voté n'a pas participé au match
  def test_voted_for_doit_avoir_joue
    voter     = create_test_user(email: "voter4@example.com", first_name: "Voter", last_name: "Quatre")
    voted_for = create_test_user(email: "voted4@example.com", first_name: "Voted", last_name: "Quatre")
    match     = create_completed_match(user: voter)
    # Seul voter est inscrit comme approved
    MatchUser.create!(user: voter, match: match, status: "approved", role: "joueur")

    vote = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    refute vote.valid?, "On ne peut pas voter pour quelqu'un qui n'a pas participé au match"
    assert vote.errors[:base].any? { |e| e.include?("participé") }
  end

  # Cas d'erreur : un match non encore terminé ne permet pas de voter
  def test_vote_invalide_si_match_non_termine
    voter     = create_test_user(email: "voter5@example.com", first_name: "Voter", last_name: "Cinq")
    voted_for = create_test_user(email: "voted5@example.com", first_name: "Voted", last_name: "Cinq")
    sport     = Sport.create!(name: "Football VF", slug: "football_vote_future", icon: "⚽")
    # Match futur → pas encore terminé.
    # Celui-ci est dans le futur donc il passe normalement la validation de date.
    match = Match.create!(
      title:       "Match Futur Vote",
      place:       "Terrain",
      date:        Date.tomorrow,
      time:        1.hour.from_now, # dans le futur pour passer la validation 30min
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        voter,
      sport:       sport
    )
    add_approved_players(match: match, voter: voter, voted_for: voted_for)

    vote = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    refute vote.valid?, "On ne peut pas voter avant la fin du match"
    assert vote.errors[:base].any? { |e| e.include?("terminé") }
  end

  # Cas d'erreur : un match terminé il y a plus de 7 jours → fenêtre dépassée
  def test_vote_invalide_si_fenetre_depassee
    voter     = create_test_user(email: "voter6@example.com", first_name: "Voter", last_name: "Six")
    voted_for = create_test_user(email: "voted6@example.com", first_name: "Voted", last_name: "Six")
    match     = create_old_match(user: voter)
    add_approved_players(match: match, voter: voter, voted_for: voted_for)

    vote = MatchVote.new(voter: voter, voted_for: voted_for, match: match)
    refute vote.valid?, "On ne peut pas voter après la fenêtre de 7 jours"
    assert vote.errors[:base].any? { |e| e.include?("7 jours") }
  end
end
