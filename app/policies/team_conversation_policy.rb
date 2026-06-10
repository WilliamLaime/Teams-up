# frozen_string_literal: true

# Policy Pundit pour les conversations d'équipe (chat de groupe d'une Team).
# Le "record" est une Team — chaque équipe possède un chat de groupe
# accessible uniquement à ses membres.
class TeamConversationPolicy < ApplicationPolicy
  # Seuls les membres de l'équipe peuvent voir le chat
  def show?
    record.team_members.exists?(user: user)
  end
end
