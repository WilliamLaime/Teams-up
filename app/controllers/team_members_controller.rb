class TeamMembersController < ApplicationController
  before_action :set_team
  before_action :set_team_member

  # DELETE /teams/:team_id/team_members/:id — captain retire un membre
  def destroy
    authorize @team_member

    removed_user = @team_member.user
    @team_member.destroy

    # Notifie le membre retiré
    Notification.create(
      user:    removed_user,
      actor:   current_user,
      message: "Tu as été retiré de l'équipe \"#{@team.name}\".",
      link:    teams_path
    )

    redirect_to @team, notice: "#{removed_user.profil&.first_name} a été retiré de l'équipe."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_team_member
    @team_member = @team.team_members.find(params[:id])
  end
end
