module InboxAgentConversationAccess
  extend ActiveSupport::Concern

  ACCESS_MODES = %w[all assigned_participating_or_team].freeze

  included do
    validates :agent_conversation_access, inclusion: { in: ACCESS_MODES }
  end

  def restricted_agent_conversation_access?
    agent_conversation_access == 'assigned_participating_or_team'
  end
end
