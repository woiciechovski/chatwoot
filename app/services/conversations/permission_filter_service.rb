class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account, plan_hint_selective_filter: false)
    @conversations = conversations
    @user = user
    @account = account
    @plan_hint_selective_filter = plan_hint_selective_filter
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    permitted_conversations = if @plan_hint_selective_filter
                                hinted_accessible_conversations
                              else
                                conversations.where(inbox: user.inboxes.where(account_id: account.id))
                              end

    permitted_conversations = restrict_agent_conversation_access(permitted_conversations)

    permitted_conversations.where.not(id: ConversationFlowExecution.in_triage.where(account_id: account.id).select(:conversation_id))
  end

  def restrict_agent_conversation_access(permitted_conversations)
    return permitted_conversations unless account_user&.agent?

    restricted_inbox_ids = user.inboxes.where(
      account_id: account.id,
      agent_conversation_access: 'assigned_participating_or_team'
    ).select(:id)
    return permitted_conversations unless restricted_inbox_ids.exists?

    restricted_inbox_conversations = permitted_conversations.where(inbox_id: restricted_inbox_ids)
    permitted_conversations.where.not(inbox_id: restricted_inbox_ids)
                           .or(restricted_inbox_conversations.where(assignee_id: user.id))
                           .or(restricted_inbox_conversations.where(id: participant_conversation_ids))
                           .or(restricted_inbox_conversations.where(team_id: user_team_ids))
  end

  def participant_conversation_ids
    ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)
  end

  def user_team_ids
    user.teams.where(account_id: account.id).select(:id)
  end

  # Same rows as accessible_conversations. `inbox_id + 0` keeps the planner from
  # driving the query through an inbox scan, which it grossly misestimates when a
  # highly selective filter (e.g. labels) is present on large accounts (CW-7787).
  def hinted_accessible_conversations
    conversations.where(
      '(conversations.inbox_id + 0) IN (
        SELECT inbox_members.inbox_id FROM inbox_members
        INNER JOIN inboxes ON inboxes.id = inbox_members.inbox_id
        WHERE inbox_members.user_id = :user_id AND inboxes.account_id = :account_id
      )',
      user_id: user.id, account_id: account.id
    )
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
