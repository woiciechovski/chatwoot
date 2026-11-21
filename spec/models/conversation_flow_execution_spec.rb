require 'rails_helper'

RSpec.describe ConversationFlowExecution do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:flow) { create(:conversation_flow, account: account, created_by: creator, enabled: true) }

  describe '.in_triage' do
    it 'includes reserved, transferring, and failed executions only' do
      conversations = Array.new(4) { create(:conversation, account: account, inbox: inbox) }
      statuses = %w[reserved transferring failed completed]

      executions = conversations.zip(statuses).map do |conversation, status|
        described_class.create!(
          account: account,
          conversation: conversation,
          conversation_flow: flow,
          status: status,
          reserved_at: Time.current
        )
      end

      expect(described_class.in_triage).to match_array(executions.first(3))
    end
  end

  it 'allows only one execution for a conversation' do
    conversation = create(:conversation, account: account, inbox: inbox)
    described_class.create!(account: account, conversation: conversation, conversation_flow: flow, status: :reserved, reserved_at: Time.current)

    duplicate = described_class.new(account: account, conversation: conversation, conversation_flow: flow, status: :reserved,
                                    reserved_at: Time.current)

    expect(duplicate).not_to be_valid
  end
end
