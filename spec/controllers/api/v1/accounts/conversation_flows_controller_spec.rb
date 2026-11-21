require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ConversationFlowsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  it 'creates a flow and maps account inboxes' do
    post "/api/v1/accounts/#{account.id}/conversation_flows",
         headers: administrator.create_new_auth_token,
         params: { conversation_flow: { name: 'Main', description: 'Inbound routing', enabled: true, inbox_ids: [inbox.id] } }

    expect(response).to have_http_status(:created)
    expect(inbox.reload.conversation_flow).to have_attributes(name: 'Main', enabled: true, created_by_id: administrator.id)
  end

  it 'updates flow configuration and activation state' do
    flow = create(:conversation_flow, account: account, created_by: administrator, name: 'Old')

    patch "/api/v1/accounts/#{account.id}/conversation_flows/#{flow.id}",
          headers: administrator.create_new_auth_token,
          params: { conversation_flow: { name: 'Updated', enabled: true, inbox_ids: [inbox.id] } }

    expect(response).to have_http_status(:success)
    expect(flow.reload).to have_attributes(name: 'Updated', enabled: true, updated_by_id: administrator.id)
    expect(inbox.reload.conversation_flow).to eq(flow)
  end

  it 'rejects an agent' do
    get "/api/v1/accounts/#{account.id}/conversation_flows", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an inbox from another account' do
    other_inbox = create(:inbox)

    expect do
      post "/api/v1/accounts/#{account.id}/conversation_flows",
           headers: administrator.create_new_auth_token,
           params: { conversation_flow: { name: 'Cross-account', inbox_ids: [other_inbox.id] } }
    end.not_to change(ConversationFlow, :count)

    expect(response).to have_http_status(:not_found)
  end
end
