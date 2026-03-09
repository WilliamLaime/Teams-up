class Notification < ApplicationRecord
  belongs_to :user

  # Scope pour récupérer uniquement les notifications non lues
  scope :unread, -> { where(read: false) }

  # Scope pour trier du plus récent au plus ancien
  scope :recent, -> { order(created_at: :desc) }
end
