module ConversationFlowInbox
  extend ActiveSupport::Concern

  included do
    validate :validate_conversation_flow_account
    validate :validate_active_conversation_flow_conflict

    belongs_to :conversation_flow, optional: true, inverse_of: :inboxes
  end

  private

  def validate_conversation_flow_account
    return if conversation_flow.blank? || conversation_flow.account_id == account_id

    errors.add(:conversation_flow, :invalid)
  end

  def validate_active_conversation_flow_conflict
    return unless will_save_change_to_conversation_flow_id? && conversation_flow&.enabled?

    previous_flow_id = conversation_flow_id_in_database
    return if previous_flow_id.blank? || previous_flow_id == conversation_flow_id
    return unless ConversationFlow.enabled.exists?(id: previous_flow_id, account_id: account_id)

    errors.add(:conversation_flow, :taken)
  end
end
