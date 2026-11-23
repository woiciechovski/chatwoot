require 'rails_helper'

RSpec.describe '/api/v1/accounts/{account.id}/contacts/:id/attachments', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox_1) { create(:inbox, account: account) }
  let(:inbox_2) { create(:inbox, account: account) }
  let(:contact_inbox_1) { create(:contact_inbox, contact: contact, inbox: inbox_1) }
  let(:contact_inbox_2) { create(:contact_inbox, contact: contact, inbox: inbox_2) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:unknown) { create(:user, account: account, role: nil) }

  before do
    create(:inbox_member, user: agent, inbox: inbox_1)

    conversation_1 = create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1)
    conversation_2 = create(:conversation, account: account, inbox: inbox_2, contact: contact, contact_inbox: contact_inbox_2)

    create(:message, :with_attachment, conversation: conversation_1, account: account, inbox: inbox_1, message_type: 'incoming')
    create(:message, :with_attachment, conversation: conversation_2, account: account, inbox: inbox_2, message_type: 'incoming')
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/attachments' do
    context 'when unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is logged in' do
      context 'with user as administrator' do
        it 'returns attachments from all the contact conversations' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments",
              headers: admin.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 2
          expect(json_response['meta']['total_count']).to eq 2
        end

        it 'serialises the conversation display id as conversation_id' do
          conversation = contact.conversations.first

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments",
              headers: admin.create_new_auth_token

          payload = response.parsed_body['payload']
          attachment = payload.find { |a| a['conversation_id'] == conversation.display_id }
          expect(attachment).not_to be_nil
          expect(attachment).to include('id', 'message_id', 'data_url', 'file_type', 'created_at', 'sender')
          expect(attachment['data_url']).to include(
            "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments/#{attachment['id']}/download"
          )
          expect(attachment['data_url']).not_to include('/rails/active_storage/')
        end
      end

      it 'does not expose external media URLs through the Contact API' do
        message = create(
          :message,
          account: account,
          inbox: inbox_1,
          conversation: contact.conversations.first,
          message_type: 'incoming'
        )
        external_attachment = message.attachments.create!(
          account: account,
          file_type: :image,
          external_url: 'https://cdn.example.com/private-contact.jpg'
        )

        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments",
            headers: admin.create_new_auth_token

        serialized_attachment = response.parsed_body['payload'].find do |item|
          item['id'] == external_attachment.id
        end
        expect(serialized_attachment['data_url']).to eq('')
        expect(serialized_attachment['thumb_url']).to eq('')
        expect(response.body).not_to include('cdn.example.com/private-contact.jpg')
      end

      context 'with user as agent' do
        it 'returns attachments only from inboxes the agent has access to' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments",
              headers: agent.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 1
          expect(json_response['meta']['total_count']).to eq 1
        end
      end

      context 'with user as unknown role' do
        it 'returns no attachments' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments",
              headers: unknown.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload']).to be_empty
        end
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:contact_id/attachments/:id/download' do
    it 'downloads an attachment for an authorized contact conversation' do
      attachment = Attachment.last

      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments/#{attachment.id}/download",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.body).to eq(attachment.file.download)
    end

    it 'does not download attachments from conversations the agent cannot see' do
      hidden_attachment = Attachment.last

      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments/#{hidden_attachment.id}/download",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end
end
