# AccountDeletionMailer — email de confirmation RGPD suite à la suppression de compte
# L'user est DÉJÀ détruit avant l'exécution de ce job (via SolidQueue).
# On ne peut donc pas utiliser des AR objects — seulement des scalaires.
class AccountDeletionMailer < ApplicationMailer

  # Email de confirmation : ton compte a été supprimé (RGPD art. 17)
  # Paramètres scalaires pour compatibilité avec SolidQueue (pas de GlobalID sur un user détruit)
  #
  # @param user_email  [String] email du compte supprimé
  # @param user_name   [String] display_name (prénom + nom ou email)
  # @param deleted_at  [Time]   timestamp de suppression (pour enregistrement légal)
  def account_deleted(user_email:, user_name:, deleted_at:)
    @user_email = user_email
    @user_name  = user_name
    @deleted_at = deleted_at

    mail(
      to:      user_email,
      subject: "Confirmation — Ton compte Team-Up a été supprimé"
    )
  end
end
