require 'rails_helper'

RSpec.describe Conversations::VisibleUsers do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:inbox, account: account, agent_conversation_access: 'assigned_participating_or_team')
  end
  let(:team) { create(:team, account: account) }
  let(:team_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }

  before do
    create(:inbox_member, inbox: inbox, user: team_agent)
    create(:team_member, team: team, user: team_agent)
  end

  it 'applies custom role limits after the inbox access rule' do
    account_user = team_agent.account_users.find_by!(account: account)
    account_user.update!(custom_role: create(:custom_role, account: account, permissions: ['conversation_participating_manage']))

    recipients = described_class.new(conversation: conversation, users: inbox.members).perform

    expect(recipients).to be_empty
  end
end
