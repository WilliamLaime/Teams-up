require "test_helper"

# Tests d'intégration pour MatchVotesController.
# Gère les votes "homme du match" :
#   POST /matches/:match_id/match_votes → créer un vote
# Conditions :
#   - Voter et voted_for doivent avoir participé au match (approved)
#   - Le match doit être terminé et dans la fenêtre de 7j
#   - On ne peut pas voter pour soi-même
class MatchVotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @voter     = create_test_user(email: "mv_voter@example.com",  first_name: "Voter",    last_name: "Ctrl")
    @voted_for = create_test_user(email: "mv_voted@example.com",  first_name: "VotedFor", last_name: "Ctrl")

    # Match terminé il y a 2h (dans la fenêtre des 7j)
    @sport = Sport.create!(name: "Football MV Ctrl", slug: "football_mv_ctrl", icon: "⚽")
    # On utilise save(validate: false) car le modèle interdit la création
    # d'un match dans le passé. On simule ici un match déjà terminé.
    @match = Match.new(
      title:       "Match Vote Ctrl",
      place:       "Terrain",
      date:        2.hours.ago.to_date,
      time:        2.hours.ago,
      players_needed: 10,
      level:       "Tout niveau", # champ obligatoire
      user:        @voter,
      sport:       @sport
    )
    @match.save(validate: false)
    # Inscrit les deux joueurs comme approuvés
    MatchUser.create!(user: @voter,     match: @match, status: "approved", role: "joueur")
    MatchUser.create!(user: @voted_for, match: @match, status: "approved", role: "joueur")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /matches/:match_id/match_votes — créer un vote
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le vote est créé et redirige vers root_path
  def test_post_match_votes_cree_le_vote
    sign_in @voter
    assert_difference "MatchVote.count", 1 do
      post match_match_votes_path(@match), params: {
        match_vote: { voted_for_id: @voted_for.id }
      }
    end
    # Après une création réussie, redirection vers root_path (fallback_location)
    assert_redirected_to root_path
    assert_not_nil flash[:notice], "Un flash notice doit être présent après succès"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_post_match_votes_redirige_si_non_connecte
    assert_no_difference "MatchVote.count" do
      post match_match_votes_path(@match), params: {
        match_vote: { voted_for_id: @voted_for.id }
      }
    end
    assert_response :redirect, "Un visiteur non connecté doit être redirigé"
  end

  # Cas d'erreur : Pundit bloque si on essaie de voter pour soi-même
  def test_post_match_votes_interdit_de_voter_pour_soi_meme
    sign_in @voter
    assert_no_difference "MatchVote.count" do
      # @voter essaie de voter pour lui-même → MatchVotePolicy#create? retourne false
      post match_match_votes_path(@match), params: {
        match_vote: { voted_for_id: @voter.id }
      }
    end
    # Pundit lève NotAuthorizedError → redirection avec alert
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert doit être présent quand on essaie de voter pour soi-même"
  end

  # Cas d'erreur : on ne peut pas voter deux fois dans le même match
  def test_post_match_votes_echoue_si_deja_vote
    sign_in @voter
    # Premier vote → succès
    post match_match_votes_path(@match), params: {
      match_vote: { voted_for_id: @voted_for.id }
    }
    # Deuxième vote → doit échouer (unicité voter/match)
    assert_no_difference "MatchVote.count" do
      post match_match_votes_path(@match), params: {
        match_vote: { voted_for_id: @voted_for.id }
      }
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert doit être présent si on a déjà voté"
  end
end
