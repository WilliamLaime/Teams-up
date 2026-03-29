# Charge la gem de validation d'email (format + MX record DNS)
require 'valid_email2'

# Modèle pour les messages envoyés via le formulaire de contact.
# Le formulaire est public — pas de relation avec User.
class ContactMessage < ApplicationRecord
  # ── Validations ──────────────────────────────────────────────────────────
  # Tous les champs sont obligatoires
  validates :prenom,  presence: true
  validates :nom,     presence: true
  validates :email,   presence: true
  # Validation personnalisée : vérifie le format ET l'existence réelle du domaine (MX record)
  # ValidEmail2::Address fait un lookup DNS pour confirmer que le domaine accepte des emails
  # → "test@domaine-inexistant.xyz" sera rejeté
  # → "user@gmail.com" sera accepté
  validate  :email_valide_et_existant
  validates :sujet,   presence: true
  validates :message, presence: true

  # ── Scopes ───────────────────────────────────────────────────────────────
  # Messages non lus — utilisé dans l'admin pour le badge compteur
  scope :unread, -> { where(lu: false) }
  # Tri du plus récent au plus ancien
  scope :recent, -> { order(created_at: :desc) }

  # ── Callbacks Turbo Stream ────────────────────────────────────────────────
  # IMPORTANT : on ne peut pas utiliser le même symbole (:broadcast_admin_badge) dans
  # after_create_commit ET after_update_commit — Rails 8 déduplique par nom de symbole
  # et le second enregistrement écrase le premier (le create serait ignoré).
  # Solution : utiliser une lambda pour le create, symbole uniquement pour le update.

  # Quand un nouveau message est créé :
  #   → Lambda pour éviter la collision avec after_update_commit :broadcast_admin_badge
  #   → Insère la nouvelle ligne en haut du tableau si l'admin est sur la page
  after_create_commit -> { broadcast_admin_badge }, :broadcast_new_message

  # Quand l'état lu/non-lu change : met à jour uniquement le badge
  after_update_commit :broadcast_admin_badge, if: :saved_change_to_lu?

  private

  # Vérifie que l'email a un format correct ET que le domaine existe réellement
  # On ne lance cette vérification que si l'email est présent (presence: true s'en charge sinon)
  def email_valide_et_existant
    return if email.blank?

    # ValidEmail2::Address analyse l'adresse email
    adresse = ValidEmail2::Address.new(email)

    # valid? vérifie le format, valid_mx? vérifie l'existence du domaine via DNS
    unless adresse.valid? && adresse.valid_mx?
      errors.add(:email, "n'est pas valide ou n'existe pas")
    end
  end

  # Insère la nouvelle ligne en tête du tableau ET sa modale dans le container dédié.
  # Déclenché uniquement à la création (after_create_commit).
  # Si l'admin n'est pas sur la page /admin/contact_messages, le broadcast est ignoré silencieusement.
  def broadcast_new_message
    # Prepend = insère en premier dans le <tbody id="contact_messages_tbody">
    Turbo::StreamsChannel.broadcast_prepend_to(
      "admin_contact_messages",
      target:  "contact_messages_tbody",
      partial: "admin/contact_messages/contact_message",
      locals:  { msg: self }
    )
    # Append = ajoute la modale dans le <div id="contact_messages_modals">
    Turbo::StreamsChannel.broadcast_append_to(
      "admin_contact_messages",
      target:  "contact_messages_modals",
      partial: "admin/contact_messages/contact_message_modal",
      locals:  { msg: self }
    )
    # Supprime la ligne "état vide" si elle est encore présente dans le DOM
    # (cas où l'admin était sur la page avec 0 messages au chargement)
    # Si l'élément n'existe pas dans le DOM, ce broadcast est ignoré silencieusement
    Turbo::StreamsChannel.broadcast_remove_to(
      "admin_contact_messages",
      target: "contact_messages_empty"
    )
  end

  # Envoie les indicateurs visuels mis à jour à tous les admins connectés
  # — Badge "1" sur l'onglet Formulaires dans l'admin nav
  # — Point vert sur l'avatar dans la navbar principale
  # — Point vert inline dans le dropdown Administration
  def broadcast_admin_badge
    Rails.logger.info "[ContactMessage] broadcast_admin_badge déclenché — id=#{id}, lu=#{lu}"

    # Calcule le nombre de messages non lus une seule fois
    unread = ContactMessage.unread.count
    Rails.logger.info "[ContactMessage] unread count = #{unread}"

    # HTML inline — DOIT être marqué html_safe sinon Rails échappe les < > en &lt; &gt;
    # badge_html : span vert avec le compteur, ou vide si tout est lu
    badge_html  = (unread > 0 ? "<span class='admin-nav-badge'>#{unread}</span>" : "").html_safe
    # dot_html : point vert sur l'avatar
    dot_html    = (unread > 0 ? "<span class='navbar-admin-dot' aria-label='Messages non lus'></span>" : "").html_safe
    # inline_html : point vert à droite de "Administration" dans le dropdown
    inline_html = (unread > 0 ? "<span class='navbar-admin-dot navbar-admin-dot--inline' aria-label='Messages non lus'></span>" : "").html_safe

    # broadcast_update_to = met à jour le innerHTML du wrapper fixe sans supprimer l'élément lui-même
    Turbo::StreamsChannel.broadcast_update_to(
      "admin_contact_messages",
      target: "admin-nav-unread-badge",
      html:   badge_html
    )

    Turbo::StreamsChannel.broadcast_update_to(
      "admin_contact_messages",
      target: "navbar-admin-avatar-dot",
      html:   dot_html
    )

    Turbo::StreamsChannel.broadcast_update_to(
      "admin_contact_messages",
      target: "navbar-admin-inline-dot",
      html:   inline_html
    )

    Rails.logger.info "[ContactMessage] broadcast badge envoyé — unread=#{unread}"
  end
end
