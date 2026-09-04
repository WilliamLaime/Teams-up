class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, # Envoie un email de confirmation à l'inscription — bloque la connexion tant que l'email n'est pas vérifié
         :omniauthable, omniauth_providers: [:google_oauth2] # Activation de la connexion via Google
  # dependent: :destroy supprime le profil automatiquement quand l'user est supprimé
  has_one :profil, dependent: :destroy

  # Attributs virtuels : ils n'existent pas en base sur users,
  # mais permettent au formulaire d'inscription de les recevoir
  # et au controller de les transmettre au Profil.
  attr_accessor :first_name, :last_name

  # Regexp de validation du mot de passe :
  # (?=.*[A-Z])   => au moins 1 lettre majuscule
  # (?=.*\d)      => au moins 1 chiffre
  # (?=.*[[:punct:]]) => au moins 1 symbole (!, @, #, $, etc.)
  # \A...\z ancrent le début et la fin de la chaîne
  # .* entre les lookaheads et \z est indispensable : il "consomme" le reste du string
  # Sans ce .*, la regex exige que la chaîne soit vide entre \A et \z → validation toujours échouée
  PASSWORD_REGEX = /\A(?=.*[A-Z])(?=.*\d)(?=.*[[:punct:]]).*\z/

  validates :password,
            format: {
              with: PASSWORD_REGEX,
              message: "doit contenir au moins 6 caractères, une majuscule, un chiffre et un symbole"
            },
            # On skip la validation de format pour les users OAuth (provider présent) :
            # leur mot de passe est un token aléatoire qu'ils n'utiliseront jamais.
            # Devise.friendly_token ne génère pas de symbole → la regex échouerait sinon.
            if: -> { password_required? && provider.blank? }

  # Validations uniquement à la création du compte (on: :create)
  # Sans ça, Devise crée l'User même si le prénom/nom est vide,
  # car la validation du Profil arrive trop tard et son erreur est ignorée.
  validates :first_name, presence: { message: "Le prénom est obligatoire" }, on: :create
  validates :last_name,  presence: { message: "Le nom est obligatoire" },    on: :create

  # Valeurs autorisées pour le genre
  GENRES = %w[femme homme autre].freeze

  # Valide que le genre est l'une des valeurs autorisées si renseigné
  # allow_nil: true → les anciens comptes (genre non rempli) restent valides
  validates :genre, inclusion: { in: GENRES, message: "n'est pas valide" }, allow_nil: true
  # ── Équipes ───────────────────────────────────────────────────────────────
  has_many :captained_teams, class_name: "Team", foreign_key: "captain_id", dependent: :destroy
  has_many :team_members,    dependent: :destroy
  has_many :teams,           through: :team_members
  has_many :team_invitations_received, class_name: "TeamInvitation", foreign_key: "invitee_id", dependent: :destroy
  has_many :team_invitations_sent,     class_name: "TeamInvitation", foreign_key: "inviter_id", dependent: :destroy

  # Vrai si au moins une équipe dont je suis capitaine a un nouveau membre
  # non encore "vu" (arrivé après captain_members_seen_at, ou created_at si null).
  # Sert au point de notification global dans la navbar.
  def has_new_captained_members?
    Team.where(captain_id: id)
        .joins(:team_members)
        .where(team_members: { role: "member" })
        .where("team_members.created_at > COALESCE(teams.captain_members_seen_at, teams.created_at)")
        .exists?
  end

  has_many :match_users, dependent: :destroy
  has_many :matchs, through: :match_users
  # Inscriptions aux tournois (feature Tournoi)
  has_many :tournament_users, dependent: :destroy
  has_many :tournaments, through: :tournament_users
  # Accusés de lecture des chats de match de tournoi. dependent: :destroy est ici
  # obligatoire, pas décoratif : la clé étrangère bloquerait la suppression du
  # compte tant qu'un accusé subsiste.
  has_many :tournament_match_chat_reads, dependent: :destroy
  has_many :notifications, dependent: :destroy
  # Subscriptions Web Push : un user peut avoir plusieurs appareils/navigateurs enregistrés
  has_many :push_subscriptions, dependent: :destroy
  # Identités Slack liées (une par workspace) — permet de poster/s'inscrire depuis Slack
  has_many :slack_identities, dependent: :destroy

  # Vrai si l'utilisateur a lié au moins un compte Slack.
  # Sert à afficher/masquer les contrôles Slack (case dans le formulaire de match,
  # bouton "Partager sur Slack") et à autoriser l'inscription depuis Slack.
  def slack_linked?
    slack_identities.any?
  end
  # Relation vers les achievements débloqués par cet utilisateur
  has_many :user_achievements, dependent: :destroy
  has_many :achievements, through: :user_achievements

  # Sports pratiqués par l'utilisateur (relation many-to-many via user_sports)
  has_many :user_sports, dependent: :destroy
  has_many :sports, through: :user_sports

  # Avis laissés par cet utilisateur (il est le reviewer)
  has_many :avis_donnes, class_name: "Avis", foreign_key: "reviewer_id",      dependent: :destroy
  # Avis reçus par cet utilisateur (il est le joueur noté)
  has_many :avis_recus,  class_name: "Avis", foreign_key: "reviewed_user_id", dependent: :destroy

  # Votes "homme du match" donnés par cet utilisateur
  has_many :votes_donnes, class_name: "MatchVote", foreign_key: "voter_id", dependent: :destroy
  # Votes "homme du match" reçus par cet utilisateur
  has_many :votes_recus,  class_name: "MatchVote", foreign_key: "voted_for_id", dependent: :destroy

  # Sport actuellement actif (dernier sport sélectionné dans la navbar)
  belongs_to :current_sport, class_name: "Sport", optional: true

  # ── Système d'amis ────────────────────────────────────────────────────────
  # Demandes d'ami initiées par cet utilisateur (il a cliqué "Ajouter")
  has_many :friendships, dependent: :destroy
  has_many :friends, through: :friendships

  # Demandes d'ami reçues par cet utilisateur (quelqu'un lui a envoyé une demande)
  has_many :inverse_friendships, class_name: "Friendship", foreign_key: "friend_id", dependent: :destroy
  has_many :inverse_friends, through: :inverse_friendships, source: :user

  # Vérifie si self et other_user sont amis (demande acceptée dans un sens ou l'autre)
  def friends_with?(other_user)
    friendships.accepted.exists?(friend_id: other_user.id) ||
      inverse_friendships.accepted.exists?(user_id: other_user.id)
  end

  # Retourne tous les amis dont la demande a été acceptée (dans les deux sens)
  def all_friends
    accepted_sent     = friendships.accepted.pluck(:friend_id)
    accepted_received = inverse_friendships.accepted.pluck(:user_id)
    User.where(id: accepted_sent + accepted_received)
  end

  # Vérifie si self a déjà envoyé une demande en attente à other_user
  def pending_request_sent_to?(other_user)
    friendships.pending.exists?(friend_id: other_user.id)
  end

  # Vérifie si other_user a envoyé une demande en attente à self
  def pending_request_from?(other_user)
    inverse_friendships.pending.exists?(user_id: other_user.id)
  end

  # Retourne la demande d'ami en attente reçue de other_user (pour pouvoir l'accepter/refuser)
  def pending_friendship_from(other_user)
    inverse_friendships.pending.find_by(user_id: other_user.id)
  end

  # Retourne le rang du joueur selon son xp_level (calculé dans Profil)
  # Utilisé par la player card pour choisir le thème visuel
  def rank
    level = profil&.xp_level || 1
    case level
    when 1..2   then "bronze"
    when 3..4   then "silver"
    when 5..6   then "gold"
    when 7..8   then "platinum"
    else             "emerald"
    end
  end

  # Libellé affiché quand un joueur n'a ni prénom ni nom renseigné.
  # SÉCURITÉ : on ne retombe JAMAIS sur l'email — cette méthode est appelée dans des vues
  # et des mails vus par d'autres utilisateurs, l'email d'autrui n'a rien à y faire.
  FALLBACK_DISPLAY_NAME = "Joueur".freeze

  # Retourne "Prénom Nom" si renseigné, sinon un libellé neutre
  # Utilisé partout dans les vues pour afficher l'identité d'un joueur
  def display_name
    full = [profil&.first_name, profil&.last_name].compact.join(' ').strip
    full.present? ? full : FALLBACK_DISPLAY_NAME
  end

  # Retourne "Prénom N." (prénom + initiale du nom) pour les contextes compacts
  # où l'on n'affiche que le prénom : l'initiale du nom permet de distinguer
  # deux joueurs homonymes (ex. deux "Williame"). Si aucun prénom n'est
  # renseigné, on retombe sur display_name (email en dernier recours).
  def short_name
    first   = profil&.first_name.to_s.strip
    initial = profil&.last_name.to_s.strip.first
    return display_name if first.blank?

    initial.present? ? "#{first} #{initial.upcase}." : first
  end

  # ── Recherche de joueurs à inviter ──────────────────────────────────────────
  #
  # Utilisée par les autocomplétions d'invitation (équipe, co-organisateur de tournoi).
  #
  # SÉCURITÉ : la recherche approximative (ILIKE) ne porte QUE sur le prénom et le nom.
  # L'email, lui, est comparé en égalité exacte : on peut donc inviter quelqu'un dont on
  # connaît déjà l'adresse, mais pas énumérer les comptes de l'application en cherchant
  # « @gmail.com ». Voir docs/SECURITE-RGPD.md.
  def self.search_for_invite(query)
    q = query.to_s.strip
    return none if q.blank?

    joins(:profil)
      .includes(:profil)
      .where(
        "profils.first_name ILIKE :like OR profils.last_name ILIKE :like OR users.email = :exact",
        like: "%#{sanitize_sql_like(q)}%",
        exact: q.downcase
      )
  end

  # ── Identifiant public temporaire pour les invitations ──────────────────────
  #
  # Les autocomplétions d'invitation (équipe, co-organisateur de tournoi) doivent
  # désigner un joueur sans faire circuler son email dans le HTML ni dans le JSON.
  # On utilise un `signed_id` Rails : une chaîne signée par l'application, donc
  # infalsifiable, cantonnée à un usage (`purpose`) et à une durée de vie courte.
  #
  # À NE PAS confondre avec un token sécurisé : un signed_id n'est pas révocable,
  # d'où l'expiration courte.
  INVITE_SGID_PURPOSE = :team_invite
  INVITE_SGID_EXPIRY  = 1.hour

  def invite_sgid
    signed_id(purpose: INVITE_SGID_PURPOSE, expires_in: INVITE_SGID_EXPIRY)
  end

  # Retourne le User correspondant, ou nil si le sgid est absent, forgé, expiré
  # ou émis pour un autre usage. Ne lève jamais d'exception (contrairement à find_signed!).
  def self.find_by_invite_sgid(sgid)
    return nil if sgid.blank?

    find_signed(sgid, purpose: INVITE_SGID_PURPOSE)
  end

  # Méthode appelée lors du retour depuis Google OAuth
  # Elle cherche un user existant avec le même uid+provider, ou le crée
  def self.from_omniauth(auth)
    # On cherche d'abord un user déjà connecté avec ce compte Google
    # Si pas trouvé, on en crée un nouveau (find_or_create_by)
    user = where(provider: auth.provider, uid: auth.uid).first

    # Si l'user existe déjà via OAuth, on s'assure qu'il est confirmé et on le retourne
    if user
      # Auto-confirme si ce n'est pas déjà fait — Google a déjà vérifié l'email
      user.update(confirmed_at: Time.current) if user.confirmed_at.nil?
      return user
    end

    # Sinon, on cherche par email (cas où l'user a un compte classique avec ce même email)
    user = find_by(email: auth.info.email)

    if user
      # L'user a un compte classique, on y associe son compte Google
      # On le confirme aussi — puisqu'il s'est authentifié via Google, l'email est valide
      user.update(provider: auth.provider, uid: auth.uid, confirmed_at: user.confirmed_at || Time.current)
    else
      # Nouvel utilisateur : on crée le compte avec un mot de passe aléatoire
      # (il n'en aura pas besoin puisqu'il se connectera toujours via Google)

      # Prénom et nom récupérés depuis les données Google — utilisés pour l'User ET le Profil
      google_first_name = auth.info.first_name.presence || auth.info.name&.split&.first || "Google"
      google_last_name  = auth.info.last_name.presence  || auth.info.name&.split&.last  || "User"

      # create (sans !) pour récupérer un user invalide plutôt que lever une exception.
      # Le controller vérifie ensuite user.persisted? pour savoir si la création a réussi.
      user = new(
        email: auth.info.email,
        provider: auth.provider,
        uid: auth.uid,
        password: Devise.friendly_token[0, 20], # Token aléatoire — jamais utilisé par l'user
        confirmed_at: Time.current, # Google a déjà vérifié l'email
        first_name: google_first_name, # attr_accessor pour les validations on: :create
        last_name: google_last_name
      )

      # Si la sauvegarde échoue (validation inattendue), on retourne le user invalide
      # → le controller détecte persisted? == false et redirige avec un message d'erreur
      return user unless user.save

      # Crée le Profil immédiatement avec les données Google.
      # Le RegistrationsController fait ça après un signup classique — on reproduit
      # ce comportement ici pour que current_user.profil ne soit jamais nil.
      profil = user.create_profil(
        first_name: google_first_name,
        last_name: google_last_name
      )

      # Télécharge et attache la photo de profil Google si disponible.
      # rescue silencieux : l'absence de photo n'est pas bloquante pour la connexion.
      if auth.info.image.present? && profil.persisted?
        begin
          require "open-uri"
          profil.avatar.attach(
            io: URI.open(auth.info.image), # rubocop:disable Security/Open -- URL Google contrôlée par OAuth, pas une entrée utilisateur
            filename: "google_avatar.jpg",
            content_type: "image/jpeg"
          )
        rescue StandardError => e
          Rails.logger.warn("Échec téléchargement avatar Google pour user #{user.id} : #{e.message}")
        end
      end
    end

    user
  end
end
