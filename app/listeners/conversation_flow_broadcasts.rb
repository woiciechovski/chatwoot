module ConversationFlowBroadcasts
  private

  def conversation_user_tokens(account, conversation)
    return user_tokens(account, []) if conversation.flow_reserved?

    user_tokens(account, conversation.inbox.members)
  end

  def typing_event_listener_tokens(account, conversation, user)
    current_user_token = if user.is_a?(Contact)
                           conversation.contact_inbox.pubsub_token
                         elsif user.respond_to?(:pubsub_token)
                           user.pubsub_token
                         end

    tokens = conversation_user_tokens(account, conversation) + [conversation.contact_inbox.pubsub_token]
    current_user_token.present? ? tokens - [current_user_token] : tokens
  end
end
