require 'rails_helper'

RSpec.describe Rbac::AuditEvents::Recorder do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:actor) { create(:user) }

  after do
    RbacAuditEvent.where(account_id: account.id).delete_all
    AccessToken.where(owner_type: 'User', owner_id: actor.id).delete_all
    User.where(id: actor.id).delete_all
    Account.where(id: account.id).delete_all
  end

  it 'keeps a denial audit after the outer operation transaction rolls back' do
    expect do
      ActiveRecord::Base.transaction do
        begin
          Rbac::MembershipLockService.with_account(account_id: account.id) do
            raise 'protected operation denied'
          end
        rescue RuntimeError
          described_class.record_denied!(
            account: account,
            actor: actor,
            action: 'role.manage.denied'
          )
        end

        raise ActiveRecord::Rollback
      end
    end.to change { RbacAuditEvent.where(account: account, action: 'role.manage.denied').count }.by(1)

    expect(RbacAuditEvent.where(account: account, actor: actor, action: 'role.manage.denied')).to exist
  end
end
