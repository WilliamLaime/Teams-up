# ── Chat d'organisation d'un match de tournoi ─────────────────────────────────
# Charge le fil d'une confrontation dans la modale partagée du tableau (un seul
# turbo-frame pour toutes les cartes — cf. tournaments/_tmatch_chat_modal).
#
# Volontairement une seule action : ce chat ne s'indexe pas, ne se liste pas et
# n'apparaît pas dans la sidebar globale. Il ne se trouve qu'en cliquant la bulle
# de sa propre carte, ce qui est exactement ce qu'on veut d'un fil privé à deux
# joueurs.
class TournamentMatchConversationsController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  def show
    # find_by plutôt que find : une carte peut disparaître (régénération d'un tour)
    # pendant qu'un joueur a la modale ouverte — on affiche un message dans le
    # frame plutôt qu'une 404 en pleine page.
    @tournament_match = TournamentMatch.find_by(id: params[:tournament_match_id])
    unless @tournament_match
      skip_authorization
      render :missing, status: :ok
      return
    end

    # Les deux joueurs + l'admin + les co-organisateurs (TournamentMatchPolicy#chat?)
    authorize @tournament_match, :chat?

    @messages = @tournament_match.messages.includes(user: :profil).order(:created_at)
    @message  = Message.new

    # Efface la pastille non-lu portée par la bulle de la carte.
    TournamentMatchChatRead.mark_read!(@tournament_match, current_user)
  end
end
