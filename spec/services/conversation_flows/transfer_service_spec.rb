require 'rails_helper'

RSpec.describe ConversationFlows::TransferService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:flow) { create(:conversation_flow, account: account, created_by: admin, enabled: true) }
  let(:team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:execution) { conversation.conversation_flow_execution }

  before do
    Current.user = nil
    inbox.update!(conversation_flow: flow)
    conversation
  end

  after do
    Current.user = nil
    Current.account = nil
  end

  it 'assigns the native conversation to the team before completing the execution' do
    result = described_class.new(execution: execution, team: team, user: admin).perform

    expect(conversation.reload.team).to eq(team)
    expect(result).to have_attributes(status: 'completed', team_id: team.id, transferred_by_id: admin.id)
    expect(result.transferred_at).to be_present
  end

  it 'rejects a team from another account without releasing the reservation' do
    other_team = create(:team)

    expect do
      described_class.new(execution: execution, team: other_team, user: admin).perform
    end.to raise_error(described_class::InvalidTeam)

    expect(execution.reload).to be_protected
    expect(conversation.reload.team).to be_nil
  end

  it 'assigns only the team when inbox auto assignment is disabled' do
    inbox.update!(enable_auto_assignment: false)
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(agent.id.to_s => 'online')

    described_class.new(execution: execution, team: team, user: admin).perform

    expect(conversation.reload).to have_attributes(team_id: team.id, assignee_id: nil)
  end

  it 'publishes the transferred conversation to the agent who could not see it in triage' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    transfer_execution = ConversationFlowExecution.find(execution.id)

    expect do
      described_class.new(execution: transfer_execution, team: team, user: admin).perform
    end.to have_enqueued_job(ActionCableBroadcastJob)
      .with(array_including(agent.pubsub_token), 'conversation.updated', hash_including(id: conversation.display_id))

    expect do
      create(:message, account: account, inbox: inbox, conversation: conversation.reload, message_type: :incoming)
    end.to have_enqueued_job(ActionCableBroadcastJob)
      .with(array_including(agent.pubsub_token), 'message.created', hash_including(conversation_id: conversation.display_id))
  end

  it 'keeps a failed assignment protected and permits a later retry' do
    allow(execution).to receive(:conversation).and_return(conversation)
    allow(conversation).to receive(:update!).and_call_original
    allow(conversation).to receive(:update!).with(team: team).and_raise(ActiveRecord::RecordInvalid.new(conversation))

    expect do
      described_class.new(execution: execution, team: team, user: admin).perform
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(execution.reload).to have_attributes(status: 'failed', failure_message: be_present, failed_at: be_present)
    expect(conversation.reload.team).to be_nil

    allow(conversation).to receive(:update!).and_call_original
    result = described_class.new(execution: execution, team: team, user: admin).perform

    expect(result).to have_attributes(status: 'completed', team_id: team.id)
  end

  it 'does not overwrite a completed transfer' do
    described_class.new(execution: execution, team: team, user: admin).perform
    second_team = create(:team, account: account)

    expect do
      described_class.new(execution: execution, team: second_team, user: admin).perform
    end.to raise_error(described_class::AlreadyTransferred)

    expect(conversation.reload.team).to eq(team)
  end
end
