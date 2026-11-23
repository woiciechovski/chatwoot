require 'rails_helper'

RSpec.describe 'Contacts RBAC authorization concurrency', type: :request do
  self.use_transactional_tests = false

  let(:first_account) { create(:account) }
  let(:second_account) { create(:account) }
  let(:user) { create(:user) }
  let(:first_contact) { create(:contact, account: first_account) }
  let(:second_contact) { create(:contact, account: second_account) }
  let(:first_membership) { create(:account_user, account: first_account, user: user, role: :agent) }
  let(:second_membership) { create(:account_user, account: second_account, user: user, role: :agent) }
  let(:first_role) { RbacRole.create!(account: first_account, name: 'First account reader') }
  let(:second_role) { RbacRole.create!(account: second_account, name: 'Second account contact editor') }

  before do
    first_role.role_permissions.create!(permission_key: 'contacts.read', scope_type: 'all_in_account')
    second_role.role_permissions.create!(permission_key: 'contacts.update', scope_type: 'all_in_account')
    first_membership.update!(rbac_managed: true, rbac_role: first_role)
    second_membership.update!(rbac_managed: true, rbac_role: second_role)
  end

  after do
    account_ids = [first_account.id, second_account.id]
    user_ids = [user.id]
    membership_ids = AccountUser.where(account_id: account_ids, user_id: user_ids).pluck(:id)
    role_ids = RbacRole.where(account_id: account_ids).pluck(:id)

    Audited::Audit.where(auditable_type: 'AccountUser', auditable_id: membership_ids).delete_all
    Audited::Audit.where(associated_type: 'Account', associated_id: account_ids).delete_all
    Contact.where(id: [first_contact.id, second_contact.id]).delete_all
    AccountUser.where(id: membership_ids).delete_all
    RbacRole.where(id: role_ids).destroy_all
    NotificationSetting.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
    Account.where(id: account_ids).delete_all
  end

  it 'evaluates separate account grants concurrently without crossing tenants' do
    ready = Queue.new
    start = Queue.new
    user_id = user.id
    checks = [
      [first_account.id, first_contact.id],
      [second_account.id, second_contact.id]
    ]

    results = checks.map do |account_id, contact_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          backend_pid = ActiveRecord::Base.connection.raw_connection.backend_pid
          account = Account.find(account_id)
          contact = Contact.find(contact_id)
          allowed = Contacts::Authorization.allowed?(
            account: account,
            user_id: user_id,
            permission: 'contacts.read',
            resource: contact
          )
          [allowed, backend_pid]
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    first_result, second_result = results.map(&:value)

    cross_account_allowed = Contacts::Authorization.allowed?(
      account: first_account,
      user_id: user_id,
      permission: 'contacts.read',
      resource: second_contact
    )
    expect(
      first_account_allowed: first_result.first,
      second_account_allowed: second_result.first,
      distinct_connections: [first_result.last, second_result.last].uniq.size,
      cross_account_allowed: cross_account_allowed
    ).to eq(
      first_account_allowed: true,
      second_account_allowed: false,
      distinct_connections: 2,
      cross_account_allowed: false
    )
  end

  it 'observes a grant revocation before a concurrent worker rechecks authorization' do
    first_account_id = first_account.id
    first_contact_id = first_contact.id
    user_id = user.id
    main_backend_pid = ActiveRecord::Base.connection.raw_connection.backend_pid
    authorization_read = Queue.new
    continue_authorization = Queue.new

    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        account = Account.find(first_account_id)
        contact = Contact.find(first_contact_id)
        backend_pid = ActiveRecord::Base.connection.raw_connection.backend_pid
        allowed_before_revocation = Contacts::Authorization.allowed?(
          account: account,
          user_id: user_id,
          permission: 'contacts.read',
          resource: contact
        )
        authorization_read << backend_pid
        continue_authorization.pop

        allowed_after_revocation = Contacts::Authorization.allowed?(
          account: Account.find(first_account_id),
          user_id: user_id,
          permission: 'contacts.read',
          resource: Contact.find(first_contact_id)
        )
        [allowed_before_revocation, allowed_after_revocation, backend_pid]
      end
    end

    worker_backend_pid = authorization_read.pop
    first_role.role_permissions.find_by!(permission_key: 'contacts.read').destroy!
    continue_authorization << true
    before_and_after = worker.value

    expect([before_and_after.first, before_and_after.second, worker_backend_pid != main_backend_pid]).to eq([true, false, true])
  end
end
