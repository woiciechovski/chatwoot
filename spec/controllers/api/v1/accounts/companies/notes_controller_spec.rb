require 'rails_helper'

RSpec.describe 'Company notes API', type: :request do
  let(:account) { create(:account) }
  let(:company) { create(:company, account: account) }
  let(:contact) do
    create(:contact, account: account, company: company, email: 'private-company-contact@example.com')
  end
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/companies/#{company.id}/notes" }

  before do
    account.enable_features!(:companies)
    create(:note, account: account, contact: contact, content: 'Contact note')
  end

  it 'preserves legacy access for unmanaged agents' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.body).to include(contact.email)
  end

  it 'requires contacts.read for managed agents before returning contact notes' do
    account.account_users.find_by!(user: agent).update!(rbac_managed: true)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(contact.email)
    expect(response.body).not_to include('Contact note')
  end
end
