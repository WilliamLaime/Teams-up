require "test_helper"

# Tests de MatchVotePolicy.
# Règles :
#   create? → l'utilisateur doit être connecté (user.present?) ET
#             ne pas voter pour lui-même (user != record.voted_for)
#
# On instancie directement la policy :
#   MatchVotePolicy.new(user, vote).create?
class MatchVotePolicyTest < ActiveSupport::TestCase
  teardown { teardown_db }

  setup do
    @voter     = create_test_user(email: "mvp_voter@example.com",  first_name: "Voter",    last_name: "Mvp")
    @voted_for = create_test_user(email: "mvp_voted@example.com",  first_name: "VotedFor", last_name: "Mvp")

    # Crée un match de référence dans le passé (pour tester la policy, pas la validation du match).
    # On utilise save(validate: false) car le modèle interdit la création d'un match passé.
    sport  = Sport.create!(name: "Football MVP", slug: "football_mvp_test", icon: "⚽")
    @match = Match.new(
      title:       "Match MVP Policy",
      place:       "Terrain",
      date:        Date.yesterday,
      time:        2.hours.ago,
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        @voter,
      sport:       sport
    )
    @match.save(validate: false)

    # Construit un vote (non persisté — on teste la policy seule)
    @vote = MatchVote.new(voter: @voter, voted_for: @voted_for, match: @match)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # create?
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur connecté votant pour quelqu'un d'autre est autorisé
  def test_create_autorise_pour_un_utilisateur_connecte_votant_pour_autrui
    assert MatchVotePolicy.new(@voter, @vote).create?,
           "Un utilisateur connecté doit pouvoir voter pour quelqu'un d'autre"
  end

  # Cas d'erreur : un utilisateur non connecté (nil) ne peut pas voter
  def test_create_interdit_pour_utilisateur_non_connecte
    # user.present? → false pour nil → create? retourne false
    refute MatchVotePolicy.new(nil, @vote).create?,
           "Un utilisateur non connecté (nil) ne doit pas pouvoir voter"
  end

  # Cas d'erreur : un utilisateur ne peut pas voter pour lui-même
  # La policy vérifie : user != record.voted_for
  def test_create_interdit_si_vote_pour_soi_meme
    # On crée un vote où voter == voted_for
    vote_self = MatchVote.new(voter: @voter, voted_for: @voter, match: @match)
    refute MatchVotePolicy.new(@voter, vote_self).create?,
           "Un utilisateur ne doit pas pouvoir voter pour lui-même"
  end

  # Edge case : voter POUR une autre personne que soi-même → toujours autorisé par la policy
  # (les autres validations — participation au match, fenêtre 7j — sont dans le modèle)
  def test_create_autorise_quel_que_soit_le_candidat_sauf_soi_meme
    autre_user = create_test_user(email: "mvp_autre@example.com", first_name: "Autre", last_name: "Mvp")
    vote_autre = MatchVote.new(voter: @voter, voted_for: autre_user, match: @match)
    assert MatchVotePolicy.new(@voter, vote_autre).create?,
           "Un utilisateur connecté peut voter pour n'importe qui d'autre que lui-même"
  end
end
