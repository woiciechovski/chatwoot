require 'rails_helper'

RSpec.describe '/api/v1/accounts/{account.id}/contacts/:id/conversations', type: :request do
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
    2.times.each do
      create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1)
      create(:conversation, account: account, inbox: inbox_2, contact: contact, contact_inbox: contact_inbox_2)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/conversations' do
    context 'when unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is logged in' do
      context 'with user as administrator' do
        it 'returns conversations from all inboxes' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: admin.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 4
        end

        it 'serves contact avatars in history through the authenticated Contact API route' do
          contact.avatar.attach(
            io: Rails.root.join('spec/assets/avatar.png').open,
            filename: 'avatar.png',
            content_type: 'image/png'
          )

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations",
              headers: admin.create_new_auth_token

          thumbnail = response.parsed_body.dig('payload', 0, 'meta', 'sender', 'thumbnail')
          expect(thumbnail).to include("/api/v1/accounts/#{account.id}/contacts/#{contact.id}/avatar/download")
          expect(thumbnail).not_to include('/rails/active_storage/')
        end

        it 'serves history message attachments through authenticated Contact API routes' do
          conversation = account.conversations.where(contact_id: contact.id).first
          message = create(:message, :with_attachment, account: account, conversation: conversation, created_at: 1.minute.from_now)
          external_attachment = message.attachments.create!(
            account: account,
            file_type: :image,
            external_url: 'https://media.example.com/private-image.png'
          )

          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations",
              headers: admin.create_new_auth_token

          history_conversation = response.parsed_body['payload'].find { |item| item['id'] == conversation.display_id }
          attachments = history_conversation.dig('messages', 0, 'attachments')
          internal_attachment = attachments.find { |item| item['id'] == message.attachments.first.id }
          external_attachment_data = attachments.find { |item| item['id'] == external_attachment.id }

          expect(internal_attachment['data_url']).to include(
            "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/attachments/#{message.attachments.first.id}/download"
          )
          expect(internal_attachment['thumb_url']).to include('?thumbnail=true')
          expect(internal_attachment['data_url']).not_to include('/rails/active_storage/')
          expect(external_attachment_data['data_url']).to eq('')
          expect(external_attachment_data['thumb_url']).to eq('')
        end
      end

      context 'with user as agent' do
        it 'returns conversations from the inboxes which agent has access to' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: agent.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 2
        end
      end

      context 'with user as unknown role' do
        it 'returns conversations from no inboxes' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: unknown.create_new_auth_token

          expect(response).to have_http_status(:success)
          json_response = response.parsed_body

          expect(json_response['payload'].length).to eq 0
        end
      end

      it 'includes older conversations with recent activity within the 25 conversation limit' do
        create_list(:conversation, 25, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1,
                                       created_at: 1.day.ago, last_activity_at: 1.day.ago)
        older_conversation = create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1,
                                                   created_at: 1.year.ago, last_activity_at: Time.current)

        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations", headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].length).to eq 25
        expect(response.parsed_body['payload'].first['id']).to eq older_conversation.display_id
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/conversations with a conversation id' do
    let!(:older) do
      create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1, created_at: 3.days.ago)
    end
    let!(:current) do
      create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1, created_at: 2.days.ago)
    end
    let!(:newer) do
      create(:conversation, account: account, inbox: inbox_1, contact: contact, contact_inbox: contact_inbox_1, created_at: 1.day.ago)
    end

    it 'returns the conversation with the ones created around it' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations",
          params: { conversation_id: current.display_id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)

      expect(response.parsed_body['payload'].pluck('id')).to eq [older.display_id, current.display_id, newer.display_id]
    end

    it 'returns no earlier conversation for the first one' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations",
          params: { conversation_id: older.display_id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)

      expect(response.parsed_body['payload'].pluck('id')).to eq [older.display_id, current.display_id]
    end

    it 'skips conversations the agent cannot access' do
      create(:conversation, account: account, inbox: inbox_2, contact: contact, contact_inbox: contact_inbox_2, created_at: 36.hours.ago)

      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/conversations",
          params: { conversation_id: current.display_id }, headers: agent.create_new_auth_token

      expect(response.parsed_body['payload'].pluck('id')).to eq [older.display_id, current.display_id, newer.display_id]
    end
  end
end
