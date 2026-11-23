require 'rails_helper'

RSpec.describe Contacts::BulkActionJob, type: :job do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:params) { { 'ids' => [1], 'labels' => { 'add' => ['vip'] } } }

  it 'invokes the bulk action service with account and user' do
    service_instance = instance_double(Contacts::BulkActionService, perform: true)

    allow(Contacts::BulkActionService).to receive(:new).and_return(service_instance)

    described_class.perform_now(account.id, user.id, params)

    expect(Contacts::BulkActionService).to have_received(:new).with(
      account: account,
      user: user,
      params: params
    )
    expect(service_instance).to have_received(:perform)
  end

  it 'does not perform a queued delete after the initiating contacts.delete grant is revoked' do
    contact = create(:contact, account: account)
    role = RbacRole.create!(account: account, name: 'Contact deleter')
    role.role_permissions.create!(permission_key: 'contacts.delete', scope_type: 'all_in_account')
    account_user = AccountUser.find_by!(account: account, user: user)
    account_user.update!(rbac_role: role)
    delete_params = { 'action_name' => 'delete', 'ids' => [contact.id] }

    described_class.perform_later(account.id, user.id, delete_params)
    role.role_permissions.delete_all
    perform_enqueued_jobs

    expect(Contact.exists?(contact.id)).to be(true)
  end

  it 'fails closed when the initiating user has no membership in the target account' do
    foreign_user = create(:user, account: create(:account))
    contact = create(:contact, account: account)

    described_class.perform_now(account.id, foreign_user.id, { 'action_name' => 'delete', 'ids' => [contact.id] })

    expect(Contact.exists?(contact.id)).to be(true)
  end
end
