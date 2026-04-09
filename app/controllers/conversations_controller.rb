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

    # find_by au lieu de find : si le match a été supprimé, on retourne une page vide
    # plutôt que de crasher (cas possible quand le sticky chat est data-turbo-permanent
    # et contient encore un lien vers un match qui n'existe plus)
    @match = Match.find_by(id: params[:id])
    unless @match
      # Match supprimé — retourne une frame vide plutôt que de crasher
      render inline: '<turbo-frame id="sticky-chat-frame">' \
                     '<div class="sticky-chat-no-selection">' \
                     "<p>Cette conversation n\\'existe plus.</p></div></turbo-frame>"
      return
    end

    # Vérifie que l'utilisateur a le droit d'accéder à ce chat
    match_user = @match.match_users.find_by(user: current_user)
    unless match_user && (match_user.approved? || match_user.role == "organisateur")
      head :forbidden
      return
    end

    @messages = @match.messages.includes(user: :profil).order(:created_at)
    @message = Message.new

    # Marque la conversation comme lue maintenant que l'utilisateur l'ouvre.
    # Le dot non-lu est retiré côté client par Stimulus (sticky-chat#selectConvo)
    # pour éviter une race condition : un broadcast_replace_to asynchrone (ActionCable)
    # peut arriver après le remove+prepend du MessagesController et écraser le nouvel item.
    match_user.update_column(:last_read_at, Time.current)
  end

  def dismiss
    skip_authorization

    # Trouve le match et la participation de l'utilisateur (find_by pour éviter le crash si supprimé)
    @match = Match.find_by(id: params[:id])
    return head(:not_found) unless @match

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
