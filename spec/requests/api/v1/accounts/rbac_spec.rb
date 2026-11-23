require 'rails_helper'

RSpec.describe 'Account RBAC API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/rbac" }
  let(:contact_permission_keys) { %w[contacts.read contacts.create contacts.update contacts.delete contacts.import contacts.export] }

  def expect_member_authorization(member, permission, allowed)
    expect(Rbac::Authorizer.allowed?(account_user: member.reload, permission: permission)).to eq(allowed)
  end

  def expect_capability_state(headers, role_id:, grant_keys:)
    get "#{base_path}/me/capabilities", headers: headers, as: :json

    body = response.parsed_body
    grants = body.dig('role', 'grants') || []
    expect(response).to have_http_status(:success)
    expect(body.dig('role', 'id')).to eq(role_id)
    expect(body.dig('domains', 0, 'authorization_state')).to eq('enforced_rbac')
    expect(grants.map { |grant| grant.fetch('permission_key') }).to match_array(grant_keys)
  end

  describe 'Contacts capability output' do
    it 'advertises only the six Contacts permissions as enforced and assignable' do
      contacts_entries = Rbac::Catalog.entries.select { |entry| entry[:module] == 'contacts' }

      expect(contacts_entries.pluck(:key)).to match_array(contact_permission_keys)
      expect(contacts_entries).to all(include(status: 'enforced', assignable: true))
    end

    it 'returns per-permission effective capability values from ContactPolicy' do
      member = AccountUser.find_by!(account: account, user: agent)
      role = RbacRole.create!(account: account, name: 'Contacts reader')
      role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
      member.update!(rbac_role: role)

      get "#{base_path}/me/capabilities", headers: agent.create_new_auth_token, as: :json

      contact_domain = response.parsed_body.fetch('domains').find { |domain| domain['module'] == 'contacts' }
      expect(response).to have_http_status(:success)
      expect(contact_domain.fetch('capabilities')).to eq(
        'contacts.read' => true,
        'contacts.create' => false,
        'contacts.update' => false,
        'contacts.delete' => false,
        'contacts.import' => false,
        'contacts.export' => false
      )
    end

    it 'reports contacts.export only when contacts.read is also granted' do
      member = AccountUser.find_by!(account: account, user: agent)
      role = RbacRole.create!(account: account, name: 'Contacts exporter')
      role.role_permissions.create!(permission_key: 'contacts.export', scope_type: 'all_in_account')
      member.update!(rbac_managed: true, rbac_role: role)

      get "#{base_path}/me/capabilities", headers: agent.create_new_auth_token, as: :json

      contact_domain = response.parsed_body.fetch('domains').find { |domain| domain['module'] == 'contacts' }
      expect(response).to have_http_status(:success)
      expect(contact_domain.fetch('capabilities')).to include('contacts.export' => false, 'contacts.read' => false)

      role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')

      get "#{base_path}/me/capabilities", headers: agent.create_new_auth_token, as: :json

      contact_domain = response.parsed_body.fetch('domains').find { |domain| domain['module'] == 'contacts' }
      expect(contact_domain.fetch('capabilities')).to include('contacts.export' => true, 'contacts.read' => true)
    end
  end

  describe 'GET /permissions' do
    it 'requires an authenticated account member' do
      get "#{base_path}/permissions", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the fixed catalog with Contacts active and the other modules planned' do
      get "#{base_path}/permissions", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      permissions = response.parsed_body.fetch('permissions')
      expect(permissions.select { |entry| entry['module'] == 'contacts' }).to all(
        include('status' => 'enforced', 'assignable' => true)
      )
      expect(permissions.reject { |entry| entry['module'] == 'contacts' }).to all(
        include('status' => 'planned', 'assignable' => false)
      )
    end

    it 'does not allow AgentBot or PlatformApp principals to use the human administration API' do
      agent_bot = create(:agent_bot, account: account)
      platform_app = create(:platform_app)
      create(:platform_app_permissible, platform_app: platform_app, permissible: account)

      get "#{base_path}/roles", headers: { api_access_token: agent_bot.access_token.token }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(RbacAuditEvent.last).to have_attributes(actor: agent_bot, result: 'denied')

      get "#{base_path}/roles", headers: { api_access_token: platform_app.access_token.token }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(RbacAuditEvent.last).to have_attributes(actor: platform_app, result: 'denied')
    end
  end

  describe 'role management' do
    it 'allows only native administrators and records denied management attempts' do
      post "#{base_path}/roles", headers: agent.create_new_auth_token,
                                 params: { role: { name: 'Support' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(RbacRole.count).to eq(0)
      expect(RbacAuditEvent.last).to have_attributes(action: 'role.create.denied', result: 'denied')
      expect(RbacAuditEvent.last.details).to eq({})
    end

    it 'records service denials after the protected lock transaction has rolled back' do
      account_user = create(:account_user, account: account, role: :administrator)
      role = RbacRole.create!(account: account, name: 'Support')
      request_transaction_depth = ActiveRecord::Base.connection.open_transactions
      expect(Rbac::AuditEvents::Recorder).to receive(:record_denied!).and_wrap_original do |method, **arguments|
        expect(ActiveRecord::Base.connection.open_transactions).to eq(request_transaction_depth)
        method.call(**arguments)
      end

      put "#{base_path}/account_users/#{account_user.id}/role",
          headers: account_user.user.create_new_auth_token,
          params: { role_id: role.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(RbacAuditEvent.last).to have_attributes(action: 'role.assign.denied', actor: account_user, result: 'denied')
    end

    it 'does not self-assign when recording the denial fails' do
      account_user = create(:account_user, account: account, role: :administrator)
      role = RbacRole.create!(account: account, name: 'Support')
      allow(Rbac::AuditEvents::Recorder).to receive(:record_denied!).and_raise(ActiveRecord::RecordNotSaved)

      put "#{base_path}/account_users/#{account_user.id}/role",
          headers: account_user.user.create_new_auth_token,
          params: { role_id: role.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account_user.reload.rbac_role_id).to be_nil
    end

    it 'keeps a denied response when writing its audit event fails' do
      allow(Rbac::AuditEvents::Recorder).to receive(:record_denied!).and_raise(ActiveRecord::RecordNotSaved)

      post "#{base_path}/roles", headers: agent.create_new_auth_token,
                                 params: { role: { name: 'Support' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(RbacRole.where(account: account)).to be_empty
    end

    it 'does not label an authenticated request with missing actor context as a system event' do
      allow(Current).to receive(:account_user).and_return(nil)
      allow(Current).to receive(:user).and_return(nil)

      post "#{base_path}/roles", headers: agent.create_new_auth_token,
                                 params: { role: { name: 'Support' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(RbacAuditEvent.where(account: account, actor_type: 'System')).to be_empty
      expect(RbacRole.where(account: account)).to be_empty
    end

    it 'creates and lists account-scoped roles' do
      post "#{base_path}/roles", headers: admin.create_new_auth_token,
                                 params: { role: { name: 'Support', description: 'Customer support' } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'Support', 'lock_version' => 0, 'grants' => [])

      get "#{base_path}/roles", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |role| role['name'] }).to eq(['Support'])
    end

    it 'returns not found for a role owned by another account' do
      other_role = RbacRole.create!(account: create(:account), name: 'Private')

      get "#{base_path}/roles/#{other_role.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Private')
    end

    it 'uses expected_version and returns a conflict for a stale update' do
      role = RbacRole.create!(account: account, name: 'Support')

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Customer Support' }, expected_version: 0 }, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['lock_version']).to eq(1)

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Old Update' }, expected_version: 0 }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(role.reload.name).to eq('Customer Support')
    end

    it 'accepts an ASCII decimal-string expected_version' do
      role = RbacRole.create!(account: account, name: 'Support')

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Support N1' }, expected_version: '0' }, as: :json

      expect(response).to have_http_status(:success)
      expect(role.reload).to have_attributes(name: 'Support N1', lock_version: 1)
    end

    it 'returns invalid_version for a float and leaves the role unchanged' do
      role = RbacRole.create!(account: account, name: 'Support')

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Should Not Save' }, expected_version: 1.0 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('invalid_version')
      expect(role.reload).to have_attributes(name: 'Support', lock_version: 0)
    end

    it 'returns invalid_version for a missing expected_version' do
      role = RbacRole.create!(account: account, name: 'Support')

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Should Not Save' } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('invalid_version')
      expect(role.reload.name).to eq('Support')
    end

    it 'returns unprocessable entity when a write omits its required version' do
      role = RbacRole.create!(account: account, name: 'Support')

      patch "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                             params: { role: { name: 'Support N1' } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(role.reload.name).to eq('Support')
    end

    it 'rejects grants from a still-planned module and leaves the role unchanged' do
      role = RbacRole.create!(account: account, name: 'Support')

      put "#{base_path}/roles/#{role.id}/grants", headers: admin.create_new_auth_token,
                                                  params: {
                                                    expected_version: 0,
                                                    grants: [{ permission_key: 'companies.read', scope_type: 'all_in_account' }]
                                                  },
                                                  as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(role.reload.role_permissions).to be_empty
    end

    it 'accepts and applies all six active Contacts grants through the API' do
      role = RbacRole.create!(account: account, name: 'All Contacts')

      put "#{base_path}/roles/#{role.id}/grants", headers: admin.create_new_auth_token,
                                                  params: {
                                                    expected_version: 0,
                                                    grants: contact_permission_keys.map do |permission_key|
                                                      { permission_key: permission_key, scope_type: 'all_in_account' }
                                                    end
                                                  },
                                                  as: :json

      expect(response).to have_http_status(:success)
      expect(role.reload.role_permissions.pluck(:permission_key)).to match_array(contact_permission_keys)
    end

    it 'replaces empty grants and exposes the effective state only for the current member' do
      role = RbacRole.create!(account: account, name: 'Support')
      member = AccountUser.find_by!(account: account, user: agent)
      put "#{base_path}/roles/#{role.id}/grants", headers: admin.create_new_auth_token,
                                                  params: { expected_version: 0, grants: [] }, as: :json
      expect(response).to have_http_status(:success)

      put "#{base_path}/account_users/#{member.id}/role", headers: admin.create_new_auth_token,
                                                          params: { role_id: role.id }, as: :json
      expect(response).to have_http_status(:success)
      expect(member.reload.rbac_managed).to be(true)

      get "#{base_path}/me/capabilities", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('role', 'id')).to eq(role.id)
      domains = response.parsed_body.fetch('domains')
      expect(domains.find { |domain| domain['module'] == 'contacts' }).to include('status' => 'enforced')
      expect(domains.reject { |domain| domain['module'] == 'contacts' }).to all(include('status' => 'planned'))
    end

    it 'does not disclose or assign roles across accounts' do
      other_role = RbacRole.create!(account: create(:account), name: 'Private')
      member = AccountUser.find_by!(account: account, user: agent)

      put "#{base_path}/account_users/#{member.id}/role", headers: admin.create_new_auth_token,
                                                          params: { role_id: other_role.id }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(member.reload.rbac_role_id).to be_nil
    end

    it 'does not disclose a foreign membership identifier in its denial audit' do
      foreign_account = create(:account)
      foreign_member = create(:account_user, account: foreign_account, role: :agent)
      role = RbacRole.create!(account: account, name: 'Support')

      put(
        "#{base_path}/account_users/#{foreign_member.id}/role",
        headers: admin.create_new_auth_token,
        params: { role_id: role.id },
        as: :json
      )

      event = RbacAuditEvent.last
      expect(response).to have_http_status(:not_found)
      expect(foreign_member.reload.rbac_role_id).to be_nil
      expect(event).to have_attributes(account: account, action: 'role.assign.denied', target_type: 'AccountUser', target_id: nil)
      expect(event.actor_id).not_to eq(foreign_member.id)
    end

    it 'denies an administrator from account A in account B and audits only account B' do
      other_account = create(:account)
      create(:account_user, account: other_account, user: admin, role: :agent)
      other_path = "/api/v1/accounts/#{other_account.id}/rbac"
      foreign_membership_id = admin.account_users.find_by!(account: account).id

      post(
        "#{other_path}/roles",
        headers: admin.create_new_auth_token,
        params: { role: { name: 'Cross-account role' } },
        as: :json
      )

      event = RbacAuditEvent.last
      expect(response).to have_http_status(:unauthorized)
      expect(RbacRole.where(account: other_account)).to be_empty
      expect(event).to have_attributes(account: other_account, actor: AccountUser.find_by!(account: other_account, user: admin),
                                       action: 'role.create.denied', result: 'denied', target_id: nil)
      expect(event.details).to eq({})
      expect(event.actor_id).not_to eq(foreign_membership_id)
      expect(response.body).not_to include('Cross-account role')
    end

    it 'rechecks effective authorization after role and grant revocation with the same token' do
      member = AccountUser.find_by!(account: account, user: agent)
      role = RbacRole.create!(account: account, name: 'Support')
      role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
      member.update!(rbac_role: role)
      headers = agent.create_new_auth_token

      expect_member_authorization(member, 'contacts.read', true)
      expect_capability_state(headers, role_id: role.id, grant_keys: ['contacts.read'])

      member.update!(rbac_role: nil)
      expect(member.reload.rbac_managed).to be(true)
      expect_member_authorization(member, 'contacts.read', false)
      expect_capability_state(headers, role_id: nil, grant_keys: [])

      member.update!(rbac_role: role)
      expect_member_authorization(member, 'contacts.read', true)
      role.role_permissions.find_by!(permission_key: 'contacts.read').destroy!
      expect_member_authorization(member, 'contacts.read', false)
      expect(member.reload.rbac_managed).to be(true)
      expect_capability_state(headers, role_id: role.id, grant_keys: [])
    end

    it 'rejects inactive roles and administrator targets' do
      inactive_role = RbacRole.create!(account: account, name: 'Inactive', active: false)
      member = AccountUser.find_by!(account: account, user: agent)
      put "#{base_path}/account_users/#{member.id}/role", headers: admin.create_new_auth_token,
                                                          params: { role_id: inactive_role.id }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(member.reload.rbac_role_id).to be_nil

      admin_membership = AccountUser.find_by!(account: account, user: admin)
      active_role = RbacRole.create!(account: account, name: 'Support')
      put "#{base_path}/account_users/#{admin_membership.id}/role", headers: admin.create_new_auth_token,
                                                                    params: { role_id: active_role.id }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(admin_membership.reload.rbac_role_id).to be_nil
    end

    it 'preserves an Enterprise custom role when an RBAC assignment conflicts' do
      skip 'Enterprise custom roles are unavailable in Community mode' unless ChatwootApp.enterprise?

      member = AccountUser.find_by!(account: account, user: agent)
      custom_role = create(:custom_role, account: account)
      member.update!(custom_role: custom_role)
      rbac_role = RbacRole.create!(account: account, name: 'Support')

      put "#{base_path}/account_users/#{member.id}/role", headers: admin.create_new_auth_token,
                                                          params: { role_id: rbac_role.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(member.reload.custom_role_id).to eq(custom_role.id)
      expect(member.rbac_role_id).to be_nil
    end

    it 'allows an administrator to read the account audit trail' do
      post "#{base_path}/roles", headers: admin.create_new_auth_token, params: { role: { name: 'Support' } }, as: :json
      write_request_id = response.headers['X-Request-Id']

      get "#{base_path}/audit_events", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.fetch('data').first).to include(
        'action' => 'role.created', 'result' => 'success', 'target' => include('type' => 'RbacRole'),
        'request_id' => write_request_id
      )
    end

    it 'does not delete a role that is still assigned' do
      role = RbacRole.create!(account: account, name: 'Support')
      member = AccountUser.find_by!(account: account, user: agent)
      member.update!(rbac_role: role)

      delete "#{base_path}/roles/#{role.id}", headers: admin.create_new_auth_token,
                                              params: { expected_version: 0 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(role.reload).to be_persisted
    end

    it 'restricts audit history to native administrators' do
      get "#{base_path}/audit_events", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
