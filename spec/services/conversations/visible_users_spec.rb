require 'rails_helper'

RSpec.describe Conversations::VisibleUsers do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:inbox, account: account, agent_conversation_access: 'assigned_participating_or_team')
  end
  let(:assigned_agent) { create(:user, account: account, role: :agent) }
  let(:participant) { create(:user, account: account, role: :agent) }
  let(:team_agent) { create(:user, account: account, role: :agent) }
  let(:unrelated_agent) { create(:user, account: account, role: :agent) }
  let(:non_member_team_agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assigned_agent, team: team) }

  before do
    [assigned_agent, participant, team_agent, unrelated_agent].each do |user|
      create(:inbox_member, inbox: inbox, user: user)
    end
    create(:team_member, team: team, user: assigned_agent)
    create(:team_member, team: team, user: team_agent)
    create(:team_member, team: team, user: non_member_team_agent)
    create(:conversation_participant, account: account, conversation: conversation, user: participant)
  end

  it 'returns inbox members assigned to, participating in, or on the team for the conversation' do
    users = described_class.new(conversation: conversation, users: inbox.members).perform

    expect(users.ids).to contain_exactly(assigned_agent.id, participant.id, team_agent.id)
  end

  it 'keeps every inbox member for an inbox in the all access mode' do
    inbox.update!(agent_conversation_access: 'all')

    users = described_class.new(conversation: conversation, users: inbox.members).perform

    expect(users.ids).to contain_exactly(assigned_agent.id, participant.id, team_agent.id, unrelated_agent.id)
  end
end
