class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  # dependent: :destroy supprime le profil automatiquement quand l'user est supprimé
  has_one :profil, dependent: :destroy

  # Attributs virtuels : ils n'existent pas en base sur users,
  # mais permettent au formulaire d'inscription de les recevoir
  # et au controller de les transmettre au Profil.
  attr_accessor :first_name, :last_name

  # Validations uniquement à la création du compte (on: :create)
  # Sans ça, Devise crée l'User même si le prénom/nom est vide,
  # car la validation du Profil arrive trop tard et son erreur est ignorée.
  validates :first_name, presence: { message: "Le prénom est obligatoire" }, on: :create
  validates :last_name,  presence: { message: "Le nom est obligatoire" },    on: :create
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
  has_many :votes_donnes, class_name: "MatchVote", foreign_key: "voter_id",      dependent: :destroy
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
end
