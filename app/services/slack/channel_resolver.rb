# Détermine DANS QUEL workspace et QUELLE destination (channel ou DM) poster pour un
# utilisateur donné.
#
# L'utilisateur choisit d'abord un workspace (s'il en a plusieurs), puis une destination
# à l'intérieur. On résout donc le workspace AVANT la destination :
#   - workspace : celui explicitement choisi (workspace_id), sinon la 1re identité liée.
#   - channel   : `override` (choix explicite) → preferred_channel → default du workspace.
#
# Renvoie nil si l'utilisateur n'a lié aucun Slack (ou pas le workspace demandé), ou si
# aucune destination n'est déterminable → l'appelant n'envoie alors rien.
module Slack
  class ChannelResolver
    Resolution = Struct.new(:workspace, :channel_id, keyword_init: true)

    def self.for(user:, workspace_id: nil, override: nil)
      identity =
        if workspace_id.present?
          user.slack_identities.find_by(slack_workspace_id: workspace_id)
        else
          user.slack_identities.includes(:slack_workspace).first
        end
      return nil unless identity

      channel_id = override.presence || identity.preferred_channel_id.presence ||
                   identity.slack_workspace.default_channel_id.presence
      return nil unless channel_id

      Resolution.new(workspace: identity.slack_workspace, channel_id: channel_id)
    end
  end
end
