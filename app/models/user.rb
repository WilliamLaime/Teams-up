class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_one :profil
  has_many :match_users
  has_many :matchs, through: :match_users
  has_many :notifications, dependent: :destroy
end
