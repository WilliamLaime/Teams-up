class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy transfer_captain leave]

  # GET /teams — liste des équipes dont l'user est membre
  def index
    # preload (au lieu de includes) pour éviter que le JOIN du policy_scope
    # ne filtre les team_members et n'affiche que 1 membre par équipe
    @teams = policy_scope(Team).preload(:captain, :team_members).order(created_at: :desc)
  end

  # GET /teams/:id — page détail de l'équipe
  def show
    authorize @team
    # Membres avec leurs profils (évite les N+1 dans la vue)
    @team_members = @team.team_members.includes(user: :profil).order(:joined_at)
    if @team.captain?(current_user)
      # Invitations en attente (visible par le captain)
      @pending_invitations = @team.team_invitations.pending.includes(invitee: :profil)

      # Propositions en attente envoyées par les membres (visible par le captain)
      @pending_proposals = @team.team_invitations.proposed.includes(invitee: :profil, proposed_by: :profil)

      # Amis du captain qui peuvent encore être invités (pas membres, pas déjà invités)
      excluded_ids = @team.members.pluck(:id) + @team.team_invitations.pending.pluck(:invitee_id)
      @invitable_friends = current_user.all_friends.includes(:profil).where.not(id: excluded_ids)
    elsif @team.member?(current_user)
      # Amis proposables : pas déjà membres, pas déjà invités/proposés
      excluded_ids = @team.members.pluck(:id) +
                     @team.team_invitations.where(status: %w[pending proposed]).pluck(:invitee_id)
      @proposable_friends = current_user.all_friends.includes(:profil).where.not(id: excluded_ids)
    end
    # Invitation reçue par l'user connecté (pour afficher accepter/refuser)
    @my_invitation = current_user.team_invitations_received.pending.find_by(team: @team)
  end

  # GET /teams/new — formulaire de création
  def new
    @team = Team.new
    authorize @team
  end

  # POST /teams — créer une équipe
  def create
    @team = Team.new(team_params)
    @team.captain = current_user
    authorize @team

    if @team.save
      redirect_to @team, notice: "Équipe créée avec succès !"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /teams/:id/edit
  def edit
    authorize @team
  end

  # PATCH /teams/:id — modifier l'équipe (captain seulement)
  def update
    authorize @team

    if @team.update(team_params)
      redirect_to @team, notice: "Équipe mise à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /teams/:id — supprimer l'équipe (captain seulement)
  def destroy
    authorize @team

    # Notifie tous les membres avant suppression
    @team.team_members.where.not(user_id: current_user.id).each do |tm|
      Notification.create(
        user:    tm.user,
        actor:   current_user,
        message: "L'équipe \"#{@team.name}\" a été supprimée par le capitaine.",
        link:    teams_path
      )
    end

    @team.destroy
    redirect_to teams_path, notice: "L'équipe a été supprimée."
  end

  # PATCH /teams/:id/transfer_captain — transférer le capitanat
  def transfer_captain
    authorize @team

    # Le nouveau captain doit être un membre existant de l'équipe
    new_captain = User.find_by(id: params[:new_captain_id])

    unless new_captain && @team.member?(new_captain)
      redirect_to @team, alert: "Ce joueur n'est pas membre de l'équipe."
      return
    end

    # Mise à jour atomique : change le captain et les rôles dans team_members
    ActiveRecord::Base.transaction do
      # Rétrograde l'ancien captain en membre
      @team.team_members.find_by(user: current_user).update!(role: "member")
      # Promu le nouveau captain
      @team.team_members.find_by(user: new_captain).update!(role: "captain")
      # Met à jour la référence captain sur l'équipe
      @team.update!(captain: new_captain)
    end

    # Notifie le nouveau captain
    Notification.create(
      user:    new_captain,
      actor:   current_user,
      message: "Tu es maintenant le capitaine de l'équipe \"#{@team.name}\" !",
      link:    team_path(@team)
    )

    redirect_to @team, notice: "Le capitanat a été transféré à #{new_captain.profil&.first_name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @team, alert: "Erreur lors du transfert : #{e.message}"
  end

  # DELETE /teams/:id/leave — quitter l'équipe (membre non-captain)
  def leave
    authorize @team

    @team.team_members.find_by(user: current_user)&.destroy
    redirect_to teams_path, notice: "Tu as quitté l'équipe \"#{@team.name}\"."
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  # Paramètres autorisés pour la création/modification d'une équipe
  def team_params
    params.require(:team).permit(:name, :description, :badge_image, :badge_svg, :cover_image, :cover_position)
  end
end
