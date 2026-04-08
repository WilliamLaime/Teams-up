# UserMailer — emails transactionnels liés aux actions des utilisateurs
# Chaque méthode correspond à un événement métier clé dans l'application.
# Tous les emails utilisent deliver_later → envoi asynchrone via SolidQueue (non bloquant).
class UserMailer < ApplicationMailer

  # ── 1. Un joueur a rejoint ton match ──────────────────────────────────────
  # Destinataire : l'organisateur du match
  # Déclenché    : join_automatically, join_with_manual_validation, join_waiting_list
  #
  # @param match        [Match] le match concerné
  # @param joining_user [User]  le joueur qui vient de s'inscrire
  # @param status       [String] "approved", "pending", ou "waiting"
  def match_joined(match, joining_user, status: "approved")
    @match        = match
    @joining_user = joining_user
    @organizer    = match.user
    @status       = status

    mail(
      to:      @organizer.email,
      subject: "#{joining_user.display_name} a rejoint votre match !"
    )
  end

  # ── 2. Ta demande a été acceptée ou refusée ────────────────────────────────
  # Destinataire : le joueur dont la demande a été traitée
  # Déclenché    : approve, reject, promote_next_in_line
  #
  # @param match_user [MatchUser] l'inscription concernée (contient user + match)
  # @param accepted   [Boolean]  true = accepté, false = refusé
  def match_status_changed(match_user, accepted:)
    @match_user = match_user
    @match      = match_user.match
    @user       = match_user.user
    @accepted   = accepted

    subject = accepted \
      ? "✅ Tu as été accepté dans \"#{@match.title}\" !" \
      : "Ta demande pour \"#{@match.title}\" a été refusée"

    mail(to: @user.email, subject: subject)
  end

  # ── 3. Un match auquel tu participais a été annulé ─────────────────────────
  # Destinataire : chaque participant inscrit (appelé une fois par participant)
  # Déclenché    : matches#destroy (avant @match.destroy)
  #
  # @param match [Match] le match annulé (avant sa destruction en BDD)
  # @param user  [User]  le participant à notifier
  def match_cancelled(match, user)
    @match     = match
    @user      = user
    @organizer = match.user

    mail(to: @user.email, subject: "Le match \"#{match.title}\" a été annulé")
  end

  # ── 4. Un joueur a quitté ton match ───────────────────────────────────────
  # Destinataire : l'organisateur du match
  # Déclenché    : match_users#destroy (uniquement si le joueur était approuvé)
  #
  # @param match        [Match] le match concerné
  # @param leaving_user [User]  le joueur qui vient de quitter
  def match_player_left(match, leaving_user)
    @match        = match
    @leaving_user = leaving_user
    @organizer    = match.user

    mail(
      to:      @organizer.email,
      subject: "#{leaving_user.display_name} a quitté votre match"
    )
  end

  # ── 5. Tu as reçu un avis ──────────────────────────────────────────────────
  # Destinataire : le joueur noté
  # Déclenché    : avis#create après sauvegarde réussie
  #
  # @param avis [Avis] l'avis créé (contient reviewer + reviewed_user + rating)
  def avis_received(avis)
    @avis          = avis
    @reviewed_user = avis.reviewed_user
    @reviewer      = avis.reviewer
    @match         = avis.match

    mail(
      to:      @reviewed_user.email,
      subject: "#{@reviewer.display_name} t'a laissé un avis !"
    )
  end

  # ── 6. Confirmation de création de match ──────────────────────────────────
  # Destinataire : l'organisateur (créateur du match)
  # Déclenché    : matches#create après sauvegarde réussie
  #
  # @param match [Match] le match qui vient d'être créé
  def match_created(match)
    @match     = match
    @organizer = match.user

    mail(
      to:      @organizer.email,
      subject: "Votre match \"#{match.title}\" a bien été créé !"
    )
  end

  # ── 7. Rappel 24h avant le match ──────────────────────────────────────────
  # Destinataire : un participant (méthode appelée une fois par participant)
  # Déclenché    : MatchReminderJob, planifié à la création du match
  #
  # @param match [Match] le match qui approche
  # @param user  [User]  le participant à rappeler
  def match_reminder(match, user)
    @match = match
    @user  = user

    mail(
      to:      @user.email,
      subject: "⏰ Rappel — \"#{match.title}\" c'est demain !"
    )
  end
end
