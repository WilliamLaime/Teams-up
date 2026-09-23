# ── Désinscription des mails de chat, depuis le lien présent dans chaque mail ──
# GET  /notifications-email/desinscription/:token => page de confirmation
# POST /notifications-email/desinscription/:token => désactive les mails
#
# Pas besoin d'être connecté : le lien doit marcher depuis n'importe quelle
# boîte mail. C'est le token qui fait office d'autorisation — un signed_id du
# profil (signé avec la secret_key_base, dédié à cet usage via `purpose`) : il
# ne contient aucune donnée personnelle et ne peut pas être fabriqué.
#
# Pourquoi un bouton plutôt qu'une désinscription dès le GET : les antivirus de
# messagerie ouvrent les liens des mails pour les analyser, ils désinscriraient
# les gens à leur insu. Le POST sert aussi la désinscription « en un clic » des
# clients mail (en-tête List-Unsubscribe-Post, RFC 8058).
class ChatEmailUnsubscribesController < ApplicationController
  TOKEN_PURPOSE = :chat_email_unsubscribe

  skip_before_action :authenticate_user!
  # Le POST « en un clic » vient du client mail, sans jeton CSRF. Sans risque ici :
  # le token signé de l'URL est la seule preuve exigée, et l'action ne fait que
  # désactiver des mails.
  skip_forgery_protection only: :create

  before_action :set_profil

  def show
    # Le token fait office d'autorisation (cf. en-tête) : pas de policy Pundit.
    skip_authorization
  end

  def create
    skip_authorization
    @profil.update!(chat_email_notifications: false)
    @unsubscribed = true
    render :show
  end

  private

  # Token invalide ou falsifié → 404, sans dire si le profil existe.
  def set_profil
    @profil = Profil.find_signed(params[:token], purpose: TOKEN_PURPOSE)
    raise ActiveRecord::RecordNotFound if @profil.nil?
  end
end
