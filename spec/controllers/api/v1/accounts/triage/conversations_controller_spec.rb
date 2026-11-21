require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Triage::ConversationsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:flow) { create(:conversation_flow, account: account, created_by: administrator, enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:execution) do
    ConversationFlowExecution.create!(account: account, conversation: conversation, conversation_flow: flow,
                                      status: :reserved, reserved_at: Time.current)
  end

  before { execution }

  it 'lists only reserved conversations with pagination metadata' do
    get "/api/v1/accounts/#{account.id}/triage/conversations", headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body, symbolize_names: true)
    expect(body.dig(:data, :meta, :current_page)).to eq(1)
    expect(body.dig(:data, :payload).first.dig(:conversation, :id)).to eq(conversation.display_id)
  end

  it 'denies agents access to the triage queue' do
    get "/api/v1/accounts/#{account.id}/triage/conversations", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists the oldest reservations first and breaks ties by execution ID' do
    same_time_conversation = create(:conversation, account: account, inbox: inbox)
    oldest_conversation = create(:conversation, account: account, inbox: inbox)
    ConversationFlowExecution.create!(account: account, conversation: same_time_conversation, conversation_flow: flow,
                                      reserved_at: execution.reserved_at)
    ConversationFlowExecution.create!(account: account, conversation: oldest_conversation, conversation_flow: flow,
                                      reserved_at: execution.reserved_at - 1.hour)

    get "/api/v1/accounts/#{account.id}/triage/conversations", headers: administrator.create_new_auth_token

    body = JSON.parse(response.body, symbolize_names: true)
    ids = body.dig(:data, :payload).map { |entry| entry.dig(:conversation, :id) }
    expect(ids).to eq([oldest_conversation.display_id, conversation.display_id, same_time_conversation.display_id])
  end

  it 'transfers the native conversation and completes its execution' do
    team = create(:team, account: account)

    post "/api/v1/accounts/#{account.id}/triage/conversations/#{conversation.display_id}/transfer",
         headers: administrator.create_new_auth_token,
         params: { team_id: team.id }

    expect(response).to have_http_status(:success)
    expect(conversation.reload.team).to eq(team)
    expect(execution.reload).to have_attributes(status: 'completed', team_id: team.id, transferred_by_id: administrator.id)
  end

  it 'uses the native last activity sort when requested' do
    other = create(:conversation, account: account, inbox: inbox)
    ConversationFlowExecution.create!(account: account, conversation: other, conversation_flow: flow,
                                      reserved_at: execution.reserved_at + 1.hour)
    conversation.update!(last_activity_at: 1.hour.ago)
    other.update!(last_activity_at: 2.hours.ago)

    get "/api/v1/accounts/#{account.id}/triage/conversations", params: { sort_by: 'last_activity_at_asc' },
                                                               headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:success)
    ids = response.parsed_body.dig('data', 'payload').map { |entry| entry.dig('conversation', 'id') }
    expect(ids).to eq([other.display_id, conversation.display_id])
  end

  it 'supports the native sorts with search and inbox filters' do
    headers = administrator.create_new_auth_token

    Conversations::SortService::SORT_OPTIONS.each_key do |sort_by|
      get "/api/v1/accounts/#{account.id}/triage/conversations",
          params: { sort_by: sort_by, q: conversation.display_id.to_s, inbox_id: inbox.id }, headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.dig('data', 'payload').map { |entry| entry.dig('conversation', 'id') }
      expect(ids).to eq([conversation.display_id])
    end
  end

  it 'does not transfer to a team from another account' do
    other_team = create(:team)

    post "/api/v1/accounts/#{account.id}/triage/conversations/#{conversation.display_id}/transfer",
         headers: administrator.create_new_auth_token,
         params: { team_id: other_team.id }

    expect(response).to have_http_status(:not_found)
    expect(execution.reload).to be_protected
    expect(conversation.reload.team).to be_nil
  end

  it 'returns conflict when a completed conversation is submitted again' do
    execution.update!(status: :completed, team: create(:team, account: account), transferred_at: Time.current)

    post "/api/v1/accounts/#{account.id}/triage/conversations/#{conversation.display_id}/transfer",
         headers: administrator.create_new_auth_token,
         params: { team_id: create(:team, account: account).id }

    expect(response).to have_http_status(:conflict)
  end
end
