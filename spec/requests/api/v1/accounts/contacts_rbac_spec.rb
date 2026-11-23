require 'rails_helper'

RSpec.describe 'Contacts RBAC API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { account.account_users.find_by!(user: agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:contact) { create(:contact, account: account, email: 'private-contact@example.com') }

  def manage_agent_with(*permission_keys)
    role = RbacRole.create!(account: account, name: 'Contacts RBAC test role')
    permission_keys.each do |permission_key|
      role.role_permissions.create!(permission_key: permission_key, scope_type: 'all_in_account')
    end
    account_user.update!(rbac_managed: true, rbac_role: role)
  end

  it 'denies a managed agent with no Contacts grant before exposing the contact list' do
    manage_agent_with
    contact

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(contact.email)
  end

  it 'denies a managed agent with no assigned role at the Contacts API' do
    account_user.update!(rbac_managed: true, rbac_role: nil)
    private_contact = contact

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(private_contact.email)
  end

  it 'does not create a contact for a managed agent without contacts.create' do
    manage_agent_with

    expect do
      post path, headers: agent.create_new_auth_token, params: { name: 'Unauthorized contact' }, as: :json
    end.not_to change(account.contacts, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lets a contacts.read-only agent list contacts but not mutate them' do
    manage_agent_with('contacts.read')
    existing_contact = contact

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    post path, headers: agent.create_new_auth_token, params: { name: 'Read-only contact' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch(
      "#{path}/#{existing_contact.id}",
      headers: agent.create_new_auth_token,
      params: { name: 'Changed without update' },
      as: :json
    )
    expect(response).to have_http_status(:unauthorized)

    delete "#{path}/#{existing_contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(existing_contact.reload.name).not_to eq('Changed without update')
  end

  it 'lets a contacts.create-only agent create but not read, update, or delete contacts' do
    manage_agent_with('contacts.create')

    post path, headers: agent.create_new_auth_token, params: { name: 'Created contact' }, as: :json
    expect(response).to have_http_status(:success)
    created_contact = account.contacts.find_by!(name: 'Created contact')
    expect(response.body).not_to include(contact.email)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch(
      "#{path}/#{created_contact.id}",
      headers: agent.create_new_auth_token,
      params: { name: 'Changed without update' },
      as: :json
    )
    expect(response).to have_http_status(:unauthorized)

    delete "#{path}/#{created_contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(created_contact.reload.name).to eq('Created contact')
  end

  it 'lets a contacts.update-only agent update without serializing the protected contact' do
    manage_agent_with('contacts.update')
    existing_contact = contact

    patch(
      "#{path}/#{existing_contact.id}",
      headers: agent.create_new_auth_token,
      params: { name: 'Updated contact' },
      as: :json
    )

    expect(response).to have_http_status(:success)
    expect(existing_contact.reload.name).to eq('Updated contact')
    expect(response.body).not_to include(existing_contact.email)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    delete "#{path}/#{existing_contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(existing_contact).to be_persisted
  end

  it 'lets a contacts.delete-only agent delete but not read or update contacts' do
    manage_agent_with('contacts.delete')
    existing_contact = contact

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch(
      "#{path}/#{existing_contact.id}",
      headers: agent.create_new_auth_token,
      params: { name: 'Changed without update' },
      as: :json
    )
    expect(response).to have_http_status(:unauthorized)

    delete "#{path}/#{existing_contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Contact.exists?(existing_contact.id)).to be(false)
  end

  it 'combines explicit grants without allowing one Contacts permission to compensate for another' do
    manage_agent_with('contacts.read', 'contacts.update')
    existing_contact = contact

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    patch(
      "#{path}/#{existing_contact.id}",
      headers: agent.create_new_auth_token,
      params: { name: 'Updated with two grants' },
      as: :json
    )
    expect(response).to have_http_status(:success)

    post path, headers: agent.create_new_auth_token, params: { name: 'Create without grant' }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'applies the complete Contacts grant set to a managed agent through the API' do
    manage_agent_with('contacts.read', 'contacts.create', 'contacts.update', 'contacts.delete', 'contacts.import', 'contacts.export')
    existing_contact = contact

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    post path, headers: agent.create_new_auth_token, params: { name: 'All grants contact' }, as: :json
    expect(response).to have_http_status(:success)
    created_contact = account.contacts.find_by!(name: 'All grants contact')

    patch "#{path}/#{created_contact.id}", headers: agent.create_new_auth_token, params: { name: 'All grants updated' }, as: :json
    expect(response).to have_http_status(:success)

    delete "#{path}/#{existing_contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Contact.exists?(existing_contact.id)).to be(false)
  end

  it 'preserves native administrator and unmanaged agent policy behavior' do
    administrator = create(:user, account: account, role: :administrator)
    legacy_agent = create(:user, account: account, role: :agent)

    get path, headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    post path, headers: administrator.create_new_auth_token, params: { name: 'Admin contact' }, as: :json
    expect(response).to have_http_status(:success)

    get path, headers: legacy_agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    post path, headers: legacy_agent.create_new_auth_token, params: { name: 'Legacy contact' }, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'isolates contact IDs and grants for a user linked to two accounts' do
    manage_agent_with('contacts.read')
    own_contact = contact
    other_account = create(:account)
    other_contact = create(:contact, account: other_account, email: 'other-account-contact@example.com')
    other_membership = create(:account_user, account: other_account, user: agent, role: :agent)
    other_role = RbacRole.create!(account: other_account, name: 'Other account contacts reader')
    other_role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
    other_membership.update!(rbac_managed: true, rbac_role: other_role)
    auth_headers = agent.create_new_auth_token

    get path, headers: auth_headers, as: :json
    own_account_response = [response.status, response.body.include?(own_contact.email), response.body.include?(other_contact.email)]

    get "/api/v1/accounts/#{other_account.id}/contacts", headers: auth_headers, as: :json
    other_account_response = [response.status, response.body.include?(other_contact.email), response.body.include?(own_contact.email)]

    get "#{path}/#{other_contact.id}", headers: auth_headers, as: :json
    cross_account_response = [response.status, response.body.include?(other_contact.email)]

    expect([own_account_response, other_account_response, cross_account_response]).to eq(
      [[200, true, false], [200, true, false], [404, false]]
    )
  end

  it 'rechecks a reused personal token after its Contacts grant is revoked' do
    manage_agent_with('contacts.read')
    contact
    auth_headers = agent.create_new_auth_token

    get path, headers: auth_headers, as: :json
    expect(response).to have_http_status(:success)

    account_user.rbac_role.role_permissions.destroy_all

    get path, headers: auth_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'nested contact resources' do
    it 'serves contact avatars through an authenticated contacts.read endpoint' do
      manage_agent_with('contacts.read')
      existing_contact = contact
      existing_contact.avatar.attach(
        io: Rails.root.join('spec/assets/avatar.png').open,
        filename: 'avatar.png',
        content_type: 'image/png'
      )

      get "#{path}/#{existing_contact.id}/avatar/download", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('image/png')
      expect(response.body).not_to be_empty
    end

    it 'does not serve an avatar when contacts.read is absent' do
      manage_agent_with('contacts.update')
      existing_contact = contact
      existing_contact.avatar.attach(
        io: Rails.root.join('spec/assets/avatar.png').open,
        filename: 'avatar.png',
        content_type: 'image/png'
      )

      get "#{path}/#{existing_contact.id}/avatar/download", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not let contacts.read download a contact export' do
      manage_agent_with('contacts.read')
      account.contacts_export.attach(
        io: StringIO.new("id,email\n1,private@example.com\n"),
        filename: 'contacts.csv',
        content_type: 'text/csv'
      )

      get "/api/v1/accounts/#{account.id}/contacts/export/download", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('private@example.com')
    end

    it 'does not download contact exports with contacts.export but without contacts.read' do
      manage_agent_with('contacts.export')
      account.contacts_export.attach(
        io: StringIO.new("id,email\n1,exported@example.com\n"),
        filename: 'contacts.csv',
        content_type: 'text/csv'
      )

      get "/api/v1/accounts/#{account.id}/contacts/export/download", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('exported@example.com')

      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'downloads contact exports when both contacts.read and contacts.export are granted' do
      manage_agent_with('contacts.read', 'contacts.export')
      account.contacts_export.attach(
        io: StringIO.new("id,email\n1,exported@example.com\n"),
        filename: 'contacts.csv',
        content_type: 'text/csv'
      )

      get "/api/v1/accounts/#{account.id}/contacts/export/download", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.body).to include('exported@example.com')
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'requires both contacts.read and contacts.export to request an export' do
      manage_agent_with('contacts.export')

      expect do
        post "#{path}/export", headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Account::ContactsExportJob)
      expect(response).to have_http_status(:unauthorized)

      account_user.rbac_role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')

      expect do
        post "#{path}/export", headers: agent.create_new_auth_token, as: :json
      end.to have_enqueued_job(Account::ContactsExportJob)
      expect(response).to have_http_status(:success)
    end

    it 'returns contact avatar URLs through the authenticated contacts API route' do
      existing_contact = contact
      existing_contact.avatar.attach(
        io: Rails.root.join('spec/assets/avatar.png').open,
        filename: 'avatar.png',
        content_type: 'image/png'
      )

      get "#{path}/#{existing_contact.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      thumbnail = response.parsed_body.dig('payload', 'thumbnail')
      expect(thumbnail).to include("/api/v1/accounts/#{account.id}/contacts/#{existing_contact.id}/avatar/download")
      expect(thumbnail).not_to include('/rails/active_storage/')
    end

    it 'denies note and label reads without contacts.read' do
      manage_agent_with('contacts.update')
      existing_contact = contact
      note = create(:note, contact: existing_contact, account: account)

      get "#{path}/#{existing_contact.id}/notes", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{path}/#{existing_contact.id}/notes/#{note.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{path}/#{existing_contact.id}/labels", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows contacts.update to write notes and labels without contacts.read' do
      manage_agent_with('contacts.update')
      existing_contact = contact
      existing_contact.update_labels('private-label')

      post "#{path}/#{existing_contact.id}/notes",
           headers: agent.create_new_auth_token,
           params: { note: { content: 'Private note' } },
           as: :json
      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(existing_contact.notes.pluck(:content)).to include('Private note')

      post "#{path}/#{existing_contact.id}/labels",
           headers: agent.create_new_auth_token,
           params: { labels: ['vip'] },
           as: :json
      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(existing_contact.reload.label_list).to include('vip')

      get "#{path}/#{existing_contact.id}/notes", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not let contacts.read substitute for update on nested writes' do
      manage_agent_with('contacts.read')
      existing_contact = contact

      expect do
        post "#{path}/#{existing_contact.id}/notes",
             headers: agent.create_new_auth_token,
             params: { note: { content: 'Unauthorized note' } },
             as: :json
      end.not_to change(existing_contact.notes, :count)
      expect(response).to have_http_status(:unauthorized)

      post "#{path}/#{existing_contact.id}/labels",
           headers: agent.create_new_auth_token,
           params: { labels: ['vip'] },
           as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(existing_contact.reload.label_list).to be_empty
    end

    it 'requires contacts.update to remove custom attributes or an avatar' do
      manage_agent_with('contacts.read')
      existing_contact = contact
      existing_contact.update!(custom_attributes: { private: 'value' })
      existing_contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png',
                                     content_type: 'image/png')

      post(
        "#{path}/#{existing_contact.id}/destroy_custom_attributes",
        headers: agent.create_new_auth_token,
        params: { custom_attributes: ['private'] },
        as: :json
      )
      expect(response).to have_http_status(:unauthorized)
      expect(existing_contact.reload.custom_attributes).to include('private' => 'value')

      delete "#{path}/#{existing_contact.id}/avatar", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(existing_contact.reload.avatar).to be_attached
    end

    it 'allows contacts.update to remove custom attributes without exposing the contact' do
      manage_agent_with('contacts.update')
      existing_contact = contact
      existing_contact.update!(custom_attributes: { private: 'value' })
      existing_contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png',
                                     content_type: 'image/png')

      post(
        "#{path}/#{existing_contact.id}/destroy_custom_attributes",
        headers: agent.create_new_auth_token,
        params: { custom_attributes: ['private'] },
        as: :json
      )

      expect(response).to have_http_status(:success)
      expect(existing_contact.reload.custom_attributes).not_to have_key('private')
      expect(response.body).not_to include(existing_contact.email)
      expect(response.body).not_to include('value')

      delete "#{path}/#{existing_contact.id}/avatar", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(existing_contact.reload.avatar).not_to be_attached
      expect(response.body).not_to include(existing_contact.email)
    end

    it 'requires contacts.update to create an inbox link' do
      manage_agent_with('contacts.read')
      existing_contact = contact
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: agent)

      expect do
        post(
          "#{path}/#{existing_contact.id}/contact_inboxes",
          headers: agent.create_new_auth_token,
          params: { inbox_id: inbox.id },
          as: :json
        )
      end.not_to change(existing_contact.contact_inboxes, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'filters contact history through its conversation visibility policy' do
    manage_agent_with('contacts.read')
    existing_contact = contact
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, contact: existing_contact, inbox: inbox, assignee: create(:user))

    get "#{path}/#{existing_contact.id}/conversations", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('payload').pluck('id')).not_to include(conversation.display_id)
  end

  it 'limits managed integration imports to contacts-only scopes' do
    account.enable_features!('data_import')
    manage_agent_with('contacts.import')
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    validator = instance_double(DataImports::Intercom::CredentialsValidator, perform: { 'contacts' => 1 })
    allow(DataImports::Intercom::CredentialsValidator).to receive(:new).and_return(validator)

    expect do
      post "/api/v1/accounts/#{account.id}/data_imports",
           headers: agent.create_new_auth_token,
           params: { source_provider: 'intercom', access_token: 'token', import_types: ['contacts'] },
           as: :json
    end.to have_enqueued_job(DataImports::Intercom::ImportJob)
    expect(response).to have_http_status(:success)

    expect do
      post "/api/v1/accounts/#{account.id}/data_imports",
           headers: agent.create_new_auth_token,
           params: { source_provider: 'intercom', access_token: 'token', import_types: %w[contacts conversations] },
           as: :json
    end.not_to have_enqueued_job(DataImports::Intercom::ImportJob)
    expect(response).to have_http_status(:unauthorized)
    expect(account.data_imports.where(import_types: %w[contacts conversations])).to be_empty
  end

  it 'omits direct Contacts search results from global search without contacts.read' do
    manage_agent_with
    private_contact = create(:contact, account: account, name: 'Unique RBAC Contact')

    get(
      "/api/v1/accounts/#{account.id}/search",
      headers: agent.create_new_auth_token,
      params: { q: 'Unique RBAC Contact' },
      as: :json
    )

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('payload')).not_to have_key('contacts')
    expect(response.body).not_to include(private_contact.name)

    get(
      "/api/v1/accounts/#{account.id}/search/contacts",
      headers: agent.create_new_auth_token,
      params: { q: 'Unique RBAC Contact' },
      as: :json
    )
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(private_contact.name)
  end

  it 'requires contacts.update before linking a contact to a company' do
    account.enable_features!(:companies)
    manage_agent_with('contacts.read')
    company = create(:company, account: account)
    existing_contact = contact

    company_id = -> { existing_contact.reload.company_id }
    expect do
      post "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts",
           headers: agent.create_new_auth_token,
           params: { contact_id: existing_contact.id },
           as: :json
    end.not_to change(&company_id)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose a contact when contacts.update links it to a company without contacts.read' do
    account.enable_features!(:companies)
    manage_agent_with('contacts.update')
    company = create(:company, account: account)
    existing_contact = contact

    post "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts",
         headers: agent.create_new_auth_token,
         params: { contact_id: existing_contact.id },
         as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('payload', 'id')).to eq(existing_contact.id)
    expect(response.body).not_to include(existing_contact.email)
    expect(existing_contact.reload.company_id).to eq(company.id)
  end

  it 'requires read, update, and delete grants before contact merge' do
    manage_agent_with('contacts.read', 'contacts.update')
    mergee = create(:contact, account: account)

    post "/api/v1/accounts/#{account.id}/actions/contact_merge",
         headers: agent.create_new_auth_token,
         params: { base_contact_id: contact.id, mergee_contact_id: mergee.id },
         as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'does not enqueue contact bulk actions when the matching write grant is absent' do
    manage_agent_with('contacts.read')
    existing_contact = contact

    expect do
      post "/api/v1/accounts/#{account.id}/bulk_actions",
           headers: agent.create_new_auth_token,
           params: { type: 'Contact', action_name: 'add_labels', ids: [existing_contact.id], labels: { add: ['vip'] } },
           as: :json
    end.not_to have_enqueued_job(Contacts::BulkActionJob)
    expect(response).to have_http_status(:unauthorized)
    expect(existing_contact.reload.label_list).to be_empty
  end
end
