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

  it 'rechecks contacts.read before broadcasting queued contact events' do
    managed_reader = create(:user, account: account, role: :agent)
    managed_without_read = create(:user, account: account, role: :agent)
    reader_role = RbacRole.create!(account: account, name: 'Contact event reader')
    reader_role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
    managed_reader.account_users.find_by!(account: account).update!(rbac_managed: true, rbac_role: reader_role)
    managed_without_read.account_users.find_by!(account: account).update!(rbac_managed: true)

    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(managed_reader.pubsub_token, anything)
    expect(ActionCable.server).not_to receive(:broadcast).with(managed_without_read.pubsub_token, anything)

    described_class.perform_now(
      [admin.pubsub_token, managed_reader.pubsub_token, managed_without_read.pubsub_token],
      'contact.updated',
      { account_id: account.id, id: 42 }
    )
  end

  it 'honors a contacts.read revocation before delivering an already queued event' do
    managed_reader = create(:user, account: account, role: :agent)
    reader_role = RbacRole.create!(account: account, name: 'Revoked contact event reader')
    permission = reader_role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
    managed_reader.account_users.find_by!(account: account).update!(rbac_managed: true, rbac_role: reader_role)
    permission.destroy!

    expect(ActionCable.server).not_to receive(:broadcast).with(managed_reader.pubsub_token, anything)

    described_class.perform_now(
      [managed_reader.pubsub_token],
      'contact.updated',
      { account_id: account.id, id: 42 }
    )
  end

  it 'keeps a queued conversation broadcast admin-only if Flow Manager reserves it before delivery' do
    flow = create(:conversation_flow, account: account, enabled: true)
    ConversationFlowExecution.create!(
      account: account,
      conversation: conversation,
      conversation_flow: flow,
      status: :reserved,
      reserved_at: Time.current
    )
    event_data = { account_id: account.id, conversation_id: conversation.display_id }

    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, anything)
    expect(ActionCable.server).not_to receive(:broadcast).with(assigned_agent.pubsub_token, anything)
    expect(ActionCable.server).not_to receive(:broadcast).with(unrelated_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(contact_token, anything)

    described_class.perform_now(tokens, 'message.created', event_data)
  end
end
