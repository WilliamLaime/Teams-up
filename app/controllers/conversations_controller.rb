class ConversationsController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  def index
    # Scope Pundit : retourne uniquement les matchs où l'utilisateur participe
    # (approuvé ou organisateur) — remplace le filtrage manuel
    @conversations = policy_scope(Match, policy_scope_class: ConversationPolicy::Scope)
                       .order(created_at: :desc)
  end

  def show
    # find_by au lieu de find : si le match a été supprimé, on retourne une page vide
    # plutôt que de crasher (cas possible quand le sticky chat est data-turbo-permanent
    # et contient encore un lien vers un match qui n'existe plus)
    @match = Match.find_by_param(params[:id])
    unless @match
      # Match supprimé — autorise et retourne une frame vide plutôt que de crasher
      skip_authorization
      render inline: '<turbo-frame id="sticky-chat-frame">' \
                     '<div class="sticky-chat-no-selection">' \
                     "<p>Cette conversation n\\'existe plus.</p></div></turbo-frame>"
      return
    end

    # Pundit vérifie que l'utilisateur est participant approuvé ou organisateur
    authorize @match, policy_class: ConversationPolicy

    @messages = @match.messages.includes(user: :profil).order(:created_at)
    @message = Message.new

    # Marque la conversation comme lue maintenant que l'utilisateur l'ouvre.
    # Le dot non-lu est retiré côté client par Stimulus (sticky-chat#selectConvo)
    # pour éviter une race condition : un broadcast_replace_to asynchrone (ActionCable)
    # peut arriver après le remove+prepend du MessagesController et écraser le nouvel item.
    match_user = @match.match_users.find_by(user: current_user)
    match_user.update_column(:last_read_at, Time.current)
  end

    def dismiss
    # Trouve le match (find_by_param pour éviter le crash si supprimé)                                        
      @match = Match.find_by_param(params[:id])                                                                 
      unless @match                                                                                             
        skip_authorization
        return head(:not_found)                                                                                 
      end                                               

      # Pundit vérifie que l'utilisateur est participant
      authorize @match, policy_class: ConversationPolicy

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
