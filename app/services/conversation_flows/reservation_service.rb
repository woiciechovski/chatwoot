class ConversationFlows::ReservationService
  pattr_initialize [:conversation!, { incoming_message: false }]

  def perform
    return existing_execution if existing_execution
    return reserve_new_conversation unless incoming_message

    reserve_existing_conversation
  end

  private

  def reserve_new_conversation
    return if conversation.campaign_id.present?
    return if Current.user.present? && !conversation.flow_api_ingress

    flow = enabled_flow
    return unless flow

    create_execution(flow)
  end

  def reserve_existing_conversation
    Conversation.transaction do
      locked_conversation = Conversation.lock.find(conversation.id)
      execution = existing_execution
      next execution if execution
      next unless eligible_existing_conversation?(locked_conversation)

      flow = enabled_flow(locked_conversation)
      next unless flow

      create_execution(flow, locked_conversation)
    end
  end

  def eligible_existing_conversation?(candidate)
    return false if candidate.assignee_id.present? || candidate.assignee_agent_bot_id.present? || candidate.team_id.present?
    return false if candidate.campaign_id.present?

    !candidate.messages.outgoing.exists?
  end

  def enabled_flow(candidate = conversation)
    flow = candidate.inbox.conversation_flow
    flow if flow&.enabled? && flow.account_id == candidate.account_id
  end

  def existing_execution
    ConversationFlowExecution.find_by(account_id: conversation.account_id, conversation_id: conversation.id)
  end

  def create_execution(flow, candidate = conversation)
    execution = ConversationFlowExecution.create!(
      account_id: candidate.account_id,
      conversation: candidate,
      conversation_flow: flow,
      status: :reserved,
      reserved_at: Time.current
    )
    remove_agent_notifications(candidate)
    conversation.association(:conversation_flow_execution).reset
    candidate.association(:conversation_flow_execution).reset unless candidate == conversation
    execution
  end

  def remove_agent_notifications(candidate)
    Notification.where(account_id: candidate.account_id, primary_actor: candidate)
                .joins(user: :account_users)
                .where(account_users: { account_id: candidate.account_id, role: :agent })
                .destroy_all
  end
end
