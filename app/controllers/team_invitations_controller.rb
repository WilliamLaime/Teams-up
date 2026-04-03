class TeamInvitationsController < ApplicationController
  before_action :set_team
  before_action :set_invitation, only: [:update, :destroy]

  # GET /teams/:team_id/team_invitations/search?q=lucas — autocomplete JSON (captain seulement)
  def search
    authorize @team, :update? # seul le captain peut inviter

    q = params[:q].to_s.strip
    return render json: [] if q.length < 3

    # Exclut les membres déjà dans l'équipe et ceux avec une invitation en attente
    excluded_ids = @team.members.pluck(:id) + @team.team_invitations.pending.pluck(:invitee_id)

    users = User.joins(:profil)
                .where("profils.first_name ILIKE ? OR users.email ILIKE ?", "%#{q}%", "%#{q}%")
                .where.not(id: excluded_ids)
                .includes(:profil)
                .limit(8)

    render json: users.map { |u|
      {
        email:      u.email,
        first_name: u.profil&.first_name,
        last_name:  u.profil&.last_name
      }
    }
  end

  # POST /teams/:team_id/team_invitations — captain invite un user
  def create
    # On cherche l'invité par email ou pseudo (first_name)
    invitee = find_invitee(params[:invitee_query])

    if invitee.nil?
      redirect_to @team, alert: "Aucun joueur trouvé avec cet email ou ce prénom."
      return
    end

    if invitee == current_user
      redirect_to @team, alert: "Tu ne peux pas t'inviter toi-même."
      return
    end

    if @team.member?(invitee)
      redirect_to @team, alert: "Ce joueur est déjà membre de l'équipe."
      return
    end

    @invitation = TeamInvitation.new(
      team:    @team,
      inviter: current_user,
      invitee: invitee,
      status:  "pending"
    )
    authorize @invitation

    if @invitation.save
      # Notifie l'invité
      Notification.create(
        user:    invitee,
        actor:   current_user,
        message: "#{current_user.profil&.first_name} t'a invité à rejoindre l'équipe \"#{@team.name}\".",
        link:    team_path(@team)
      )
      redirect_to @team, notice: "Invitation envoyée à #{invitee.profil&.first_name} !"
    else
      redirect_to @team, alert: @invitation.errors.full_messages.to_sentence
    end
  end

  # PATCH /teams/:team_id/team_invitations/:id — invité accepte ou refuse
  def update
    authorize @invitation

    case params[:status]
    when "accepted"
      accept_invitation
    when "refused"
      refuse_invitation
    else
      redirect_to teams_path, alert: "Action invalide."
    end
  end

  # DELETE /teams/:team_id/team_invitations/:id — captain annule une invitation
  def destroy
    authorize @invitation
    @invitation.destroy
    redirect_to @team, notice: "Invitation annulée."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_invitation
    @invitation = TeamInvitation.find(params[:id])
  end

  # Cherche un user par email ou par prénom (via son profil)
  def find_invitee(query)
    return nil if query.blank?

    User.find_by(email: query.strip.downcase) ||
      User.joins(:profil).find_by(profils: { first_name: query.strip })
  end

  # Accepte l'invitation : crée le TeamMember et met à jour le statut
  def accept_invitation
    ActiveRecord::Base.transaction do
      @invitation.update!(status: "accepted")
      @team.team_members.create!(
        user:      current_user,
        role:      "member",
        joined_at: Time.current
      )
    end

    # Notifie le captain
    Notification.create(
      user:    @team.captain,
      actor:   current_user,
      message: "#{current_user.profil&.first_name} a accepté de rejoindre l'équipe \"#{@team.name}\" !",
      link:    team_path(@team)
    )

    redirect_to @team, notice: "Tu as rejoint l'équipe \"#{@team.name}\" !"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to teams_path, alert: "Erreur : #{e.message}"
  end

  # Refuse l'invitation : met à jour le statut uniquement
  def refuse_invitation
    @invitation.update!(status: "refused")
    redirect_to teams_path, notice: "Invitation refusée."
  end
end
