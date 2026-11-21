require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::InboxScopedCounter do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:restricted_inbox) do
    create(:inbox, account: account, agent_conversation_access: 'assigned_participating_or_team')
  end
  let(:all_inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:billing_label) { create(:label, account: account, title: 'billing', show_on_sidebar: true) }
  let(:support_label) { create(:label, account: account, title: 'support', show_on_sidebar: true) }
  let(:hidden_label) { create(:label, account: account, title: 'internal', show_on_sidebar: false) }

  before do
    create(:inbox_member, user: agent, inbox: restricted_inbox)
    create(:inbox_member, user: agent, inbox: all_inbox)
    create(:team_member, user: agent, team: team)
  end

  it 'groups unread counts using the conversations visible to the agent' do
    create_unread_conversation(account: account, inbox: restricted_inbox, assignee: agent, labels: [billing_label.title])
    participating = create_unread_conversation(account: account, inbox: restricted_inbox, labels: [billing_label.title])
    create(:conversation_participant, account: account, conversation: participating, user: agent)
    create_unread_conversation(account: account, inbox: restricted_inbox, team: team, labels: [support_label.title])
    create_unread_conversation(account: account, inbox: restricted_inbox, assignee: create(:user, account: account), labels: [billing_label.title])
    create_unread_conversation(account: account, inbox: restricted_inbox, labels: [billing_label.title, hidden_label.title])
    create_unread_conversation(account: account, inbox: all_inbox, labels: [billing_label.title])

    result = described_class.new(account: account, user: agent).perform

    expect(result).to eq(
      all_count: 4,
      inboxes: { restricted_inbox.id.to_s => 3, all_inbox.id.to_s => 1 },
      labels: { billing_label.id.to_s => 3, support_label.id.to_s => 1 },
      teams: { team.id.to_s => 1 }
    )
  end
end
