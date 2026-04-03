class TeamConversationsController < ApplicationController
  # authenticate_user! déjà appliqué globalement dans ApplicationController

  def show
    skip_authorization

    # Trouve l'équipe (find_by évite un crash si l'équipe a été supprimée)
    @team = Team.find_by(id: params[:id])
    unless @team
      render inline: '<turbo-frame id="sticky-chat-frame">' \
                     '<div class="sticky-chat-no-selection">' \
                     "<p>Cette équipe n\\'existe plus.</p></div></turbo-frame>"
      return
    end

    # Seuls les membres de l'équipe peuvent voir le chat
    @team_member = @team.team_members.find_by(user: current_user)
    unless @team_member
      head :forbidden
      return
    end

    # Charge les 50 derniers messages de l'équipe
    @messages = @team.messages.includes(user: :profil).order(:created_at).last(50)
    @message = Message.new

    # Marque le chat comme lu (efface le badge non-lu dans la sidebar)
    @team_member.update_column(:chat_last_read_at, Time.current)

    # Broadcast pour retirer le badge non-lu dans la sidebar de l'utilisateur
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_conversations_#{current_user.id}",
      target: "sticky-team-convo-#{@team.id}",
      partial: "shared/team_convo_item",
      locals: { team: @team, team_member: @team_member }
    )
  end
end
