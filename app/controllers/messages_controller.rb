class MessagesController < ApplicationController
  # L'utilisateur doit être connecté pour envoyer un message
  before_action :authenticate_user!

  # Charge le match et vérifie que l'utilisateur a le droit de participer au chat
  before_action :set_match_and_check_access

  def create
    # On gère l'autorisation manuellement dans set_match_and_check_access
    # skip_authorization indique à Pundit qu'on a bien vérifié les droits
    skip_authorization

    # Crée un nouveau message associé au match et à l'utilisateur connecté
    @message = @match.messages.build(
      content: message_params[:content],
      user: current_user
    )

    if @message.save
      # 🎮 Vérifier les achievements liés aux messages envoyés
      AchievementService.new(current_user).check(:message_sent)
      # Le broadcast est géré automatiquement par after_create_commit dans le modèle
      # On réinitialise le formulaire via Turbo Stream (vide le champ texte)
      respond_to do |format|
        format.turbo_stream do
          # On envoie DEUX mises à jour Turbo Stream :
          # 1. "chat-form"        → formulaire dans la modal sur la page show du match
          # 2. "sticky-chat-form" → formulaire dans le panneau sticky (toutes les pages)
          # Si l'un des deux éléments n'existe pas dans la page, Turbo l'ignore silencieusement
          render turbo_stream: [
            turbo_stream.update(
              "chat-form",
              partial: "messages/form",
              locals: { match: @match, message: Message.new }
            ),
            turbo_stream.update(
              "sticky-chat-form",
              partial: "messages/form",
              locals: { match: @match, message: Message.new }
            )
          ]
        end
        format.html { redirect_to @match }
      end
    else
      # En cas d'erreur, on redirige simplement (message trop long, vide, etc.)
      redirect_to @match, alert: "Impossible d'envoyer le message."
    end
  end

  private

  # Charge le match depuis l'URL et vérifie que l'utilisateur est participant approuvé
  def set_match_and_check_access
    @match = Match.find(params[:match_id])

    # Récupère l'inscription de l'utilisateur à ce match
    match_user = @match.match_users.find_by(user: current_user)

    # Seuls les participants approuvés et les organisateurs peuvent écrire
    unless match_user && (match_user.approved? || match_user.role == "organisateur")
      redirect_to @match, alert: "Tu dois être participant du match pour écrire dans le chat."
    end
  end

  # Filtre les paramètres autorisés pour un message
  def message_params
    params.require(:message).permit(:content)
  end
end
