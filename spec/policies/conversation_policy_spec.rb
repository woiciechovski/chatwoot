require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:conversation) { create(:conversation, account: account) }

  permissions :destroy? do
    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end
  end

  permissions :index? do
    context 'when user is authenticated' do
      it 'allows index' do
        expect(subject).to permit(agent_context, conversation)
      end
    end
  end

  permissions :show? do
    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when agent has inbox access' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when inbox conversation access is restricted' do
      let(:inbox) do
        create(:inbox, account: account, agent_conversation_access: 'assigned_participating_or_team')
      end
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'allows a conversation assigned to the agent' do
        conversation.update!(assignee: agent)

        expect(subject).to permit(agent_context, conversation)
      end

      it 'allows a conversation where the agent participates' do
        create(:conversation_participant, conversation: conversation, account: account, user: agent)

        expect(subject).to permit(agent_context, conversation)
      end

      it 'allows a team assigned conversation when the agent belongs to the team' do
        team = create(:team, account: account)
        create(:team_member, team: team, user: agent)
        conversation.update!(team: team)

        expect(subject).to permit(agent_context, conversation)
      end

      it 'denies an unrelated conversation in the inbox' do
        expect(subject).not_to permit(agent_context, conversation)
      end

      it 'denies a team member who is not a member of the inbox' do
        team = create(:team, account: account)
        team_agent = create(:user, account: account, role: :agent)
        create(:team_member, team: team, user: team_agent)
        conversation.update!(team: team)

        team_context = {
          user: team_agent,
          account: account,
          account_user: team_agent.account_users.find_by(account: account)
        }

        expect(subject).not_to permit(team_context, conversation)
      end
    end

    context 'when agent has team access' do
      let(:team) { create(:team, account: account) }
      let(:conversation) { create(:conversation, :with_team, account: account, team: team) }

      before { create(:team_member, team: team, user: agent) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when agent lacks inbox and team access' do
      let(:conversation) { create(:conversation, account: account) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end

    context 'when an agent has inbox access to a reserved conversation' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:flow) { create(:conversation_flow, account: account, created_by: administrator, enabled: true) }

      before do
        create(:inbox_member, user: agent, inbox: inbox)
        ConversationFlowExecution.create!(account: account, conversation: conversation, conversation_flow: flow,
                                          status: :reserved, reserved_at: Time.current)
      end

      it 'denies direct access while retaining administrator access' do
        expect(subject).not_to permit(agent_context, conversation)
        expect(subject).to permit(administrator_context, conversation)
      end
    end
  end
end
