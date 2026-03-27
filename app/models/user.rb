class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
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
            if: :password_required? # Méthode Devise : n'exécute la validation que si le mot de passe est renseigné

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
  has_many :match_users, dependent: :destroy
  has_many :matchs, through: :match_users
  has_many :notifications, dependent: :destroy
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

  # Retourne "Prénom Nom" si renseigné, sinon l'email
  # Utilisé partout dans les vues pour afficher l'identité d'un joueur
  def display_name
    full = [profil&.first_name, profil&.last_name].compact.join(' ').strip
    full.present? ? full : email
  end

  # Méthode appelée lors du retour depuis Google OAuth
  # Elle cherche un user existant avec le même uid+provider, ou le crée
  def self.from_omniauth(auth)
    # On cherche d'abord un user déjà connecté avec ce compte Google
    # Si pas trouvé, on en crée un nouveau (find_or_create_by)
    user = where(provider: auth.provider, uid: auth.uid).first

    # Si l'user existe déjà via OAuth, on le retourne directement
    return user if user

    # Sinon, on cherche par email (cas où l'user a un compte classique avec ce même email)
    user = find_by(email: auth.info.email)

    if user
      # L'user a un compte classique, on y associe son compte Google
      user.update(provider: auth.provider, uid: auth.uid)
    else
      # Nouvel utilisateur : on crée le compte avec un mot de passe aléatoire
      # (il n'en aura pas besoin puisqu'il se connectera toujours via Google)
      user = create!(
        email: auth.info.email,
        provider: auth.provider,
        uid: auth.uid,
        password: Devise.friendly_token[0, 20], # Mot de passe aléatoire obligatoire pour Devise
        # first_name et last_name sont des attributs virtuels pour créer le Profil
        # On les récupère depuis les données Google
        first_name: auth.info.first_name.presence || auth.info.name&.split&.first || "Google",
        last_name: auth.info.last_name.presence || auth.info.name&.split&.last || "User"
      )
    end

    user
  end
end
