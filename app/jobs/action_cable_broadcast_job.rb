class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  def perform(members, event_name, data)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    members = members_with_current_conversation_access(members, event_name, data)
    return if members.blank?

    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    @broadcast_conversation = conversation
    broadcast_data = conversation.push_event_data.merge(account_id: data[:account_id])
    if event_name == ASSIGNEE_CHANGED
      # Keep the original assignment together even when the conversation is
      # refreshed. The dashboard checks its identity against the current owner.
      # Other events omit this field so unrelated updates cannot overwrite it.
      broadcast_data[:assignment] = {
        automatic: data[:automatic_assignment] == true,
        assignee_id: data.dig(:meta, :assignee, :id),
        assignee_type: data.dig(:meta, :assignee_type),
        updated_at: data[:updated_at]
      }
    end
    broadcast_data
  end

  def members_with_current_conversation_access(members, event_name, data)
    conversation = restricted_conversation_for_event(event_name, data)
    return members if conversation.blank?

    account = conversation.account
    user_tokens = User.where(pubsub_token: members).pluck(:pubsub_token)
    visible_user_tokens = visible_user_tokens_for(conversation)
    other_tokens = members - user_tokens
    recipient_user_tokens = user_tokens & visible_user_tokens
    administrator_tokens = account.administrators.where(pubsub_token: members).pluck(:pubsub_token)

    (other_tokens + recipient_user_tokens + administrator_tokens).uniq
  end

  def visible_user_tokens_for(conversation)
    return [] if conversation.flow_reserved?

    ::Conversations::VisibleUsers.new(
      conversation: conversation,
      users: conversation.inbox.members
    ).perform.pluck(:pubsub_token)
  end

  def restricted_conversation_for_event(event_name, data)
    return @broadcast_conversation if defined?(@broadcast_conversation)

    reference = conversation_reference(event_name, data)
    return if reference.blank?

    account = Account.find_by(id: data[:account_id])
    return if account.blank?

    conversations = account.conversations.joins(:inbox).includes(:inbox, :account, :team, :conversation_flow_execution)
    restricted_conversations = conversations.where(inboxes: { agent_conversation_access: 'assigned_participating_or_team' })
    reserved_conversations = conversations.where(
      id: ConversationFlowExecution.in_triage.where(account_id: account.id).select(:conversation_id)
    )

    restricted_conversations.or(reserved_conversations).find_by(reference.first => reference.last)
  end

  def conversation_reference(event_name, data)
    data = data.with_indifferent_access
    return [:display_id, data[:conversation_id]] if data[:conversation_id].present?
    return [:display_id, data.dig(:conversation, :id) || data[:id]] if event_name.to_s.start_with?('conversation.')

    notification_reference(data)
  end

  def notification_reference(data)
    notification = data[:notification]
    return unless notification.present? && notification[:primary_actor_type] == 'Conversation'

    [:id, notification[:primary_actor_id]]
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
