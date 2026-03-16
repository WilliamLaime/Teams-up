class ConversationsController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  def index
    # Pundit : skip_policy_scope car on filtre manuellement par current_user
    skip_policy_scope
    skip_authorization

    # Récupère les IDs des matchs où l'utilisateur est approuvé OU organisateur
    participant_match_ids = current_user.match_users
      .where("status = 'approved' OR role = 'organisateur'")
      .pluck(:match_id)

    @conversations = Match
      .where(id: participant_match_ids)
      .order(created_at: :desc)
  end

  def show
    skip_authorization

    @match = Match.find(params[:id])

    # Vérifie que l'utilisateur a le droit d'accéder à ce chat
    match_user = @match.match_users.find_by(user: current_user)
    unless match_user && (match_user.approved? || match_user.role == "organisateur")
      head :forbidden
      return
    end

    @messages = @match.messages.includes(user: :profil).order(:created_at)
    @message = Message.new

    # Marque la conversation comme lue maintenant que l'utilisateur l'ouvre
    # Cela efface le badge "non-lu" dans la sidebar via un broadcast Turbo Stream
    match_user.update_column(:last_read_at, Time.current)

    # Broadcast pour mettre à jour l'item de sidebar (retire le badge non-lu)
    broadcast_read_update(match_user)
  end

  private

  # Diffuse la mise à jour de l'item sidebar pour retirer le badge non-lu
  def broadcast_read_update(match_user)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_conversations_#{current_user.id}",
      target: "sticky-convo-#{match_user.match_id}",
      partial: "shared/sticky_convo_item",
      locals: { match: @match, match_user: match_user }
    )
  end

  def dismiss
    skip_authorization

    # Trouve le match et la participation de l'utilisateur
    @match = Match.find(params[:id])
    match_user = @match.match_users.find_by(user: current_user)

    # Marque la conversation comme dismissée avec un timestamp
    # La conversation réapparaîtra si un nouveau message est envoyé (cf. Message model)
    match_user&.update(chat_dismissed_at: Time.current)

    # Répond avec un Turbo Stream qui supprime l'item de la sidebar
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("sticky-convo-#{@match.id}")
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
