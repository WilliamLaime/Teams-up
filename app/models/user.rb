class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_one :profil

  # Attributs virtuels : ils n'existent pas en base sur users,
  # mais permettent au formulaire d'inscription de les recevoir
  # et au controller de les transmettre au Profil.
  attr_accessor :first_name, :last_name
  has_many :match_users
  has_many :matchs, through: :match_users
  has_many :notifications, dependent: :destroy
  # Relation vers les achievements débloqués par cet utilisateur
  has_many :user_achievements, dependent: :destroy
  has_many :achievements, through: :user_achievements

  # Sports pratiqués par l'utilisateur (relation many-to-many via user_sports)
  has_many :user_sports, dependent: :destroy
  has_many :sports, through: :user_sports

  # Sport actuellement actif (dernier sport sélectionné dans la navbar)
  belongs_to :current_sport, class_name: "Sport", optional: true

  # Retourne "Prénom Nom" si renseigné, sinon l'email
  # Utilisé partout dans les vues pour afficher l'identité d'un joueur
  def display_name
    full = [profil&.first_name, profil&.last_name].compact.join(' ').strip
    full.present? ? full : email
  end
end
