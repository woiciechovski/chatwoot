require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::BroadcastScope do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:inbox, account: account, agent_conversation_access: 'assigned_participating_or_team')
  end
  let(:assigned_agent) { create(:user, account: account, role: :agent) }
  let(:unrelated_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assigned_agent) }
  let(:event) { Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conversation) }

  before do
    create(:inbox_member, inbox: inbox, user: assigned_agent)
    create(:inbox_member, inbox: inbox, user: unrelated_agent)
  end

  it 'scopes the refresh recipients to agents who can see the conversation' do
    _account, recipients = described_class.new(event).perform

    expect(recipients).to contain_exactly(assigned_agent)
  end
end
