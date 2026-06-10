# frozen_string_literal: true

# Policy Pundit pour les conversations de match (chat de groupe).
# Le "record" est un Match — chaque match possède un chat de groupe
# accessible aux joueurs approuvés et à l'organisateur.
class ConversationPolicy < ApplicationPolicy
  # Scope : retourne les matchs dont l'utilisateur est participant
  # (approuvé ou organisateur) — utilisé pour lister les conversations.
  class Scope < ApplicationPolicy::Scope
    def resolve
      match_ids = user.match_users
                      .where("status = 'approved' OR role = 'organisateur'")
                      .select(:match_id)
      scope.where(id: match_ids)
    end
  end

  # Peut voir le chat du match si l'utilisateur y participe
  def show?
    participant?
  end

  # Peut masquer (dismiss) la conversation si l'utilisateur y participe
  def dismiss?
    participant?
  end

  private

  # Vérifie que l'utilisateur est un participant approuvé ou l'organisateur du match
  def participant?
    mu = record.match_users.find_by(user: user)
    mu&.approved? || mu&.role == "organisateur"
  end
end
