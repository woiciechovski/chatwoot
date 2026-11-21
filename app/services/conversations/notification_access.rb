class Conversations::NotificationAccess
  def self.visible_to_recipient?(notification)
    conversation = notification.primary_actor
    return true unless conversation.is_a?(Conversation)
    return true unless conversation.inbox.restricted_agent_conversation_access?

    account_user = notification.account.account_users.find_by(user_id: notification.user_id)
    return false if account_user.blank?

    ConversationPolicy.new(
      { user: notification.user, account: notification.account, account_user: account_user },
      conversation
    ).show?
  end
end
