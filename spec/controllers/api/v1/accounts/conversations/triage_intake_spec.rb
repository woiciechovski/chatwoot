require 'rails_helper'

RSpec.describe 'Conversation triage intake', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:flow) { create(:conversation_flow, account: account, created_by: admin, enabled: true) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: channel, conversation_flow: flow) }
  let(:contact) { create(:contact, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:params) { { contact_id: contact.id, inbox_id: inbox.id, status: 'open' } }
  let(:api_headers) { { api_access_token: admin.access_token.token } }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'protects API conversations before the separate first incoming message and the creation broadcast' do
    expect do
      post path, headers: api_headers, params: params, as: :json
    end.to have_enqueued_job(ActionCableBroadcastJob)
      .with(array_including(admin.pubsub_token), 'conversation.created', hash_including(inbox_id: inbox.id))
    id = response.parsed_body.fetch('id')
    conversation = account.conversations.find_by!(display_id: id)
    expect(conversation).to be_flow_reserved
    expect(ActionCableBroadcastJob).not_to have_been_enqueued
      .with(array_including(agent.pubsub_token), 'conversation.created', hash_including(id: id))

    get "#{path}/#{id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)

    post "#{path}/#{id}/messages", headers: api_headers, params: { message_type: 'incoming', content: 'Hello' }, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.messages.incoming.count).to eq(1)
    expect(conversation.reload).to be_flow_reserved
  end

  it 'keeps an API conversation initiated with an outgoing message out of triage' do
    post path, headers: api_headers, params: params.merge(message: { content: 'Hello' }), as: :json

    expect(response).to have_http_status(:success)
    conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))
    expect(conversation).not_to be_flow_reserved
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'keeps a conversation created from the dashboard out of triage' do
    post path, headers: admin.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:success)
    expect(account.conversations.find_by!(display_id: response.parsed_body.fetch('id'))).not_to be_flow_reserved
  end
end
