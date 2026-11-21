require 'rails_helper'

RSpec.describe ConversationFlows::ReservationService do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:flow) { create(:conversation_flow, account: account, created_by: creator, enabled: true) }

  after do
    Current.user = nil
    Current.account = nil
  end

  describe 'new conversations' do
    it 'reserves a new external conversation before commit' do
      inbox.update!(conversation_flow: flow)

      conversation = create(:conversation, account: account, inbox: inbox)

      expect(conversation.conversation_flow_execution).to have_attributes(status: 'reserved', account_id: account.id,
                                                                          conversation_flow_id: flow.id)
    end

    it 'does not reserve an agent-created conversation' do
      inbox.update!(conversation_flow: flow)
      Current.user = creator

      expect do
        create(:conversation, account: account, inbox: inbox)
      end.not_to change(ConversationFlowExecution, :count)
    end

    it 'does not reserve a conversation when the flow is disabled' do
      flow.update!(enabled: false)
      inbox.update!(conversation_flow: flow)

      expect do
        create(:conversation, account: account, inbox: inbox)
      end.not_to change(ConversationFlowExecution, :count)
    end
  end

  describe 'incoming messages on existing conversations' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      conversation
      inbox.update!(conversation_flow: flow)
    end

    it 'reserves an eligible incoming message on an unassigned conversation' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, message_type: :incoming)

      message.save!

      expect(conversation.reload.conversation_flow_execution).to have_attributes(status: 'reserved', conversation_flow_id: flow.id)
    end

    it 'does not reserve a conversation that already has an outgoing response' do
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: creator, message_type: :outgoing)
      incoming_message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact,
                                         message_type: :incoming)

      incoming_message.save!

      expect(conversation.reload.conversation_flow_execution).to be_nil
    end

    it 'returns the existing execution for duplicate reservation calls' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, message_type: :incoming)
      message.save!

      first = described_class.new(conversation: conversation, incoming_message: true).perform
      second = described_class.new(conversation: conversation, incoming_message: true).perform

      expect(second).to eq(first)
      expect(ConversationFlowExecution.where(conversation: conversation).count).to eq(1)
    end

    it 'removes existing agent notifications while preserving administrator notifications' do
      agent = create(:user, account: account, role: :agent)
      administrator = create(:user, account: account, role: :administrator)
      agent_notification = create(:notification, account: account, user: agent, primary_actor: conversation)
      admin_notification = create(:notification, account: account, user: administrator, primary_actor: conversation)
      incoming_message = build(:message, account: account, inbox: inbox, conversation: conversation,
                                         sender: conversation.contact, message_type: :incoming)

      incoming_message.save!

      expect(Notification.exists?(agent_notification.id)).to be(false)
      expect(Notification.exists?(admin_notification.id)).to be(true)
    end

    it 'does not reserve an outgoing message on an otherwise unhandled conversation' do
      outgoing_message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: creator, message_type: :outgoing)

      outgoing_message.save!

      expect(conversation.reload.conversation_flow_execution).to be_nil
    end
  end

  describe 'reserved conversations' do
    it 'rejects outgoing messages while the execution is protected' do
      inbox.update!(conversation_flow: flow)
      conversation = create(:conversation, account: account, inbox: inbox)
      message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: creator, message_type: :outgoing)

      expect(message.save).to be(false)
      expect(message.errors[:base]).to include(I18n.t('conversation_flows.errors.outgoing_message_reserved'))
    end

    it 'keeps a completed execution after a later incoming message' do
      inbox.update!(conversation_flow: flow)
      conversation = create(:conversation, account: account, inbox: inbox)
      execution = conversation.conversation_flow_execution
      execution.update!(status: :completed, transferred_at: Time.current, transferred_by: creator)
      message = build(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, message_type: :incoming)

      message.save!

      expect(conversation.reload.conversation_flow_execution).to have_attributes(status: 'completed')
      expect(ConversationFlowExecution.where(conversation: conversation).count).to eq(1)
    end
  end
end
