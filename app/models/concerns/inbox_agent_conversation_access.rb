module InboxAgentConversationAccess
  extend ActiveSupport::Concern

  ACCESS_MODES = %w[all assigned_participating_or_team].freeze

  included do
    validates :agent_conversation_access, inclusion: { in: ACCESS_MODES }
    before_update :capture_agent_visibility_change_user_ids, if: :will_save_change_to_agent_conversation_access?
    after_update_commit :invalidate_filtered_unread_counts_after_access_change, if: :saved_change_to_agent_conversation_access?
  end

  def restricted_agent_conversation_access?
    agent_conversation_access == 'assigned_participating_or_team'
  end

  private

  def capture_agent_visibility_change_user_ids
    @agent_visibility_change_user_ids = inbox_members.pluck(:user_id)
  end

  def invalidate_filtered_unread_counts_after_access_change
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).users_visibility_changed!(
      user_ids: @agent_visibility_change_user_ids
    )
  end
end
