require 'rails_helper'

RSpec.describe 'Super Admin Account Users API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/account_users/new' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/account_users/new'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      it 'shows the account user create page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/account_users/new'
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'DELETE /super_admin/account_users/:id' do
    it 'blocks removing the last administrator and records the denied recovery attempt' do
      account = create(:account)
      account_user = create(:account_user, account: account, role: :administrator)
      sign_in(super_admin, scope: :super_admin)

      delete "/super_admin/account_users/#{account_user.id}"

      expect(account_user.reload).to be_administrator
      expect(RbacAuditEvent.last).to have_attributes(
        account: account,
        actor: super_admin,
        action: 'administrator.recovery.removal.denied', result: 'denied', target_type: 'AccountUser', target_id: account_user.id
      )
    end
  end

  describe 'POST /super_admin/account_users' do
    it 'audits adding a native administrator for installation recovery' do
      account = create(:account)
      user = create(:user)
      sign_in(super_admin, scope: :super_admin)

      post '/super_admin/account_users', params: {
        account_user: { account_id: account.id, user_id: user.id, role: 'administrator' }
      }

      expect(account.account_users.find_by!(user: user)).to be_administrator
      expect(RbacAuditEvent.last).to have_attributes(
        action: 'administrator.recovery.granted', result: 'success', target_type: 'AccountUser'
      )
    end
  end
end
