class PrivateConversation < ApplicationRecord
  # sender = celui qui a initié la conversation
  belongs_to :sender, class_name: "User"
  # recipient = le destinataire
  belongs_to :recipient, class_name: "User"

  # Une conversation privée a plusieurs messages
  has_many :messages, dependent: :destroy

  # ── Trouver ou créer une conversation entre deux utilisateurs ─────────────
  # L'ordre n'a pas d'importance : entre(A, B) == entre(B, A)
  def self.between(user_a, user_b)
    # Cherche dans les deux sens possibles
    find_by(sender: user_a, recipient: user_b) ||
    find_by(sender: user_b, recipient: user_a) ||
    create!(sender: user_a, recipient: user_b)
  end

  # ── Retourner l'autre participant (pas le current_user) ───────────────────
  def other_user(current_user)
    sender == current_user ? recipient : sender
  end

  # ── Savoir si current_user a des messages non lus ─────────────────────────
  def unread_for?(user)
    last_read = last_read_at_for(user)
    if last_read.nil?
      # Jamais lu → non lu si au moins un message
      messages.exists?
    else
      # Non lu si un message a été créé après la dernière lecture
      messages.where("created_at > ?", last_read).exists?
    end
  end

  # ── Retourner le timestamp de dernière lecture pour un utilisateur ─────────
  def last_read_at_for(user)
    sender == user ? sender_last_read_at : recipient_last_read_at
  end

  # ── Marquer la conversation comme lue pour un utilisateur ─────────────────
  def mark_read_for!(user)
    if sender == user
      update_column(:sender_last_read_at, Time.current)
    else
      update_column(:recipient_last_read_at, Time.current)
    end
  end
end
