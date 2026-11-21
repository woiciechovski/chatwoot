class Conversations::VisibleUsers
  attr_reader :conversation, :users

  def initialize(conversation:, users:)
    @conversation = conversation
    @users = users
  end

  def perform
    return users unless conversation.inbox.restricted_agent_conversation_access?

    permitted_users = inbox_member_candidates
    exclude_users_denied_by_custom_roles(permitted_users)
  end

  private

  def inbox_member_candidates
    participant_user_ids = conversation.conversation_participants.where(account_id: conversation.account_id).select(:user_id)
    candidates = users.where(id: conversation.assignee_id).or(users.where(id: participant_user_ids))
    return candidates if conversation.team_id.blank?

    candidates.or(users.where(id: conversation.team.members.select(:id)))
  end

  def exclude_users_denied_by_custom_roles(candidates)
    return candidates unless AccountUser.reflect_on_association(:custom_role)

    custom_role_users = conversation.account.account_users
                                    .where(user_id: candidates.select(:id))
                                    .where.not(custom_role_id: nil)
                                    .includes(:custom_role)
                                    .to_a
    return candidates if custom_role_users.empty?

    participants = conversation.conversation_participants.pluck(:user_id)
    denied_user_ids = custom_role_users.filter_map do |account_user|
      account_user.user_id unless custom_role_allows_conversation?(account_user, participants)
    end

    candidates.where.not(id: denied_user_ids)
  end

  def custom_role_allows_conversation?(account_user, participant_user_ids)
    permissions = account_user.permissions
    return true if permissions.include?('conversation_manage')

    return true if permits_unassigned_manage?(account_user, permissions)
    return true if permits_participating_manage?(account_user, permissions, participant_user_ids)

    false
  end

  def permits_unassigned_manage?(account_user, permissions)
    return false unless permissions.include?('conversation_unassigned_manage')

    unassigned_conversation? || conversation.assignee_id == account_user.user_id
  end

  def permits_participating_manage?(account_user, permissions, participant_user_ids)
    return false unless permissions.include?('conversation_participating_manage')

    conversation.assignee_id == account_user.user_id || participant_user_ids.include?(account_user.user_id)
  end

  def unassigned_conversation?
    conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
  end
end
