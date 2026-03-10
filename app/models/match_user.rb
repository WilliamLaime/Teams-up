class MatchUser < ApplicationRecord
  belongs_to :user
  belongs_to :match

  # Statuts possibles pour une inscription
  # "waiting" = en file d'attente (match complet)
  STATUSES = ["pending", "approved", "rejected", "waiting"].freeze

  # Helpers pour vérifier le statut facilement
  def approved?
    status == "approved"
  end

  def pending?
    status == "pending"
  end

  def rejected?
    status == "rejected"
  end

  # Retourne vrai si le joueur est en file d'attente (match complet)
  def waiting?
    status == "waiting"
  end
end
