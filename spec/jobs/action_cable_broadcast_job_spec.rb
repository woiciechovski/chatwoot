require 'rails_helper'

RSpec.describe ActionCableBroadcastJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assigned_agent) { create(:user, account: account, role: :agent) }
  let(:unrelated_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assigned_agent) }
  let(:contact_token) { conversation.contact_inbox.pubsub_token }
  let(:tokens) { [admin.pubsub_token, assigned_agent.pubsub_token, unrelated_agent.pubsub_token, contact_token] }

  before do
    create(:inbox_member, inbox: inbox, user: assigned_agent)
    create(:inbox_member, inbox: inbox, user: unrelated_agent)
  end

  it 'rechecks recipients when a conversation becomes restricted after an event is queued' do
    inbox.update!(agent_conversation_access: 'assigned_participating_or_team')
    event_data = { account_id: account.id, conversation_id: conversation.display_id }

    expect(ActionCable.server).to receive(:broadcast).with(assigned_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(contact_token, anything)
    expect(ActionCable.server).not_to receive(:broadcast).with(unrelated_agent.pubsub_token, anything)

    described_class.perform_now(tokens, 'message.created', event_data)
  end

  it 'rechecks recipients for conversation updates after they are queued' do
    inbox.update!(agent_conversation_access: 'assigned_participating_or_team')

    expect(ActionCable.server).to receive(:broadcast).with(assigned_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(contact_token, anything)
    expect(ActionCable.server).not_to receive(:broadcast).with(unrelated_agent.pubsub_token, anything)

    described_class.perform_now(tokens, 'conversation.updated', conversation.push_event_data.merge(account_id: account.id))
  end

  it 'does not deliver a queued notification update after its conversation becomes inaccessible' do
    notification = create(:notification, account: account, user: unrelated_agent, primary_actor: conversation)
    inbox.update!(agent_conversation_access: 'assigned_participating_or_team')
    event_data = { account_id: account.id, notification: notification.push_event_data }

    expect(ActionCable.server).not_to receive(:broadcast).with(unrelated_agent.pubsub_token, anything)

    described_class.perform_now([unrelated_agent.pubsub_token], 'notification.updated', event_data)
  end
end
