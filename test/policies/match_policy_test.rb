require "test_helper"

class MatchPolicyTest < ActiveSupport::TestCase
  # On crée deux utilisateurs : le créateur du match et un autre utilisateur
  def setup
    @owner = users(:one)    # utilisateur qui a créé le match
    @other = users(:two)    # autre utilisateur
    @match = matches(:one)  # un match appartenant à @owner
  end

  # Tout le monde peut créer un match
  def test_create
    assert MatchPolicy.new(@owner, @match).create?
    assert MatchPolicy.new(@other, @match).create?
  end

  # Tout le monde peut voir un match
  def test_show
    assert MatchPolicy.new(@owner, @match).show?
    assert MatchPolicy.new(@other, @match).show?
  end

  # Seul le créateur peut modifier un match
  def test_update
    assert MatchPolicy.new(@owner, @match).update?
    refute MatchPolicy.new(@other, @match).update?
  end

  # Seul le créateur peut supprimer un match
  def test_destroy
    assert MatchPolicy.new(@owner, @match).destroy?
    refute MatchPolicy.new(@other, @match).destroy?
  end

  # Rencontre de tournoi : l'admin et les co-organisateurs du tournoi ont la
  # main (modifier / supprimer), pas un simple joueur. Slack reste au créateur.
  def test_tournament_organizers_can_update_and_destroy
    sport = Sport.create!(name: "Sport policy", slug: "sport-policy", icon: "🏓")
    tournament = Tournament.create!(name: "T policy", sport: sport, user: @other,
                                    format: "ronde_suisse", status: "in_progress", max_players: 8,
                                    date: Date.tomorrow, place: "Terrain")
    co_org = create_test_user(email: "policy-co@example.com")
    tournament.tournament_users.create!(user: co_org, role: "joueur", status: "approved", co_organizer: true)
    player = create_test_user(email: "policy-player@example.com")
    tournament.tournament_users.create!(user: player, role: "joueur", status: "approved")
    @match.update_column(:tournament_id, tournament.id)

    [@other, co_org].each do |organizer|
      assert MatchPolicy.new(organizer, @match).update?
      assert MatchPolicy.new(organizer, @match).destroy?
      refute MatchPolicy.new(organizer, @match).share_on_slack?
    end
    refute MatchPolicy.new(player, @match).update?
    refute MatchPolicy.new(player, @match).destroy?
    refute MatchPolicy.new(nil, @match).update?
  end

  # Le scope retourne tous les matchs pour n'importe quel utilisateur
  def test_scope
    all_matches = Match.all
    resolved = MatchPolicy::Scope.new(@owner, Match.all).resolve
    assert_equal all_matches.count, resolved.count
  end
end
