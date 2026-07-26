require "test_helper"

class SlackFavoriteDestinationTest < ActiveSupport::TestCase
  setup do
    @user = create_test_user(email: "fav@example.com", first_name: "Fav", last_name: "Test")
    @ws   = SlackWorkspace.create!(team_id: "T_FAV", team_name: "FavCorp", bot_token: "xoxb-fav")
    @identity = SlackIdentity.create!(user: @user, slack_workspace: @ws,
                                      slack_user_id: "U_FAV", slack_team_id: "T_FAV")
  end

  teardown do
    SlackFavoriteDestination.delete_all
    SlackIdentity.delete_all
    SlackWorkspace.delete_all
    teardown_db
  end

  test "valide avec channel_id et channel_name" do
    fav = @identity.slack_favorite_destinations.new(channel_id: "C1", channel_name: "#general")
    assert fav.valid?
  end

  test "channel_id et channel_name sont obligatoires" do
    fav = SlackFavoriteDestination.new(slack_identity: @identity)
    assert_not fav.valid?
    assert_includes fav.errors.attribute_names, :channel_id
    assert_includes fav.errors.attribute_names, :channel_name
  end

  test "un même channel ne peut être épinglé qu'une fois par identité" do
    @identity.slack_favorite_destinations.create!(channel_id: "C1", channel_name: "#general")
    dup = @identity.slack_favorite_destinations.new(channel_id: "C1", channel_name: "#general")
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :channel_id
  end

  test "favorite_destinations_pairs renvoie [nom, id] triés par nom" do
    @identity.slack_favorite_destinations.create!(channel_id: "C2", channel_name: "#zebra")
    @identity.slack_favorite_destinations.create!(channel_id: "C1", channel_name: "#alpha")
    assert_equal [["#alpha", "C1"], ["#zebra", "C2"]], @identity.favorite_destinations_pairs
  end

  test "supprimés avec l'identité (dependent: :destroy)" do
    @identity.slack_favorite_destinations.create!(channel_id: "C1", channel_name: "#general")
    assert_difference "SlackFavoriteDestination.count", -1 do
      @identity.destroy
    end
  end
end
