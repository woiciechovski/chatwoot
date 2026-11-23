# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'teardown after parent deletion' do
    it 'allows async membership cleanup after account and user rows are gone' do
      account_user = create(:account_user)
      account = account_user.account
      user = account_user.user

      account.delete
      user.delete
      expect(Account.exists?(account.id)).to be(false)
      expect(User.exists?(user.id)).to be(false)
      account_user.association(:account).reset
      account_user.association(:user).reset

      expect { account_user.destroy! }.not_to have_enqueued_job(Agents::DestroyJob)
      expect(described_class.exists?(account_user.id)).to be(false)
    end
  end

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      expect(account_user.user.notification_settings).not_to be_nil

      expect(account_user.user.notification_settings.first.email_conversation_creation?).to be(false)
      expect(account_user.user.notification_settings.first.email_conversation_assignment?).to be(true)
    end
  end

  describe 'work preferences' do
    it 'allows turning off one of conversations or calls' do
      expect(account_user.update(accepts_calls: false)).to be(true)
    end

    it 'rejects turning off both conversations and calls' do
      expect(account_user.update(accepts_conversations: false, accepts_calls: false)).to be(false)
      expect(account_user.errors[:base]).to include('Receive conversations or Receive voice calls must stay on')
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  describe 'RBAC role assignment' do
    it 'keeps new account links in legacy mode' do
      expect(account_user.rbac_managed).to be(false)
      expect(account_user.rbac_role).to be_nil
    end

    it 'marks a link as RBAC-managed when a role is assigned and keeps it managed after removal' do
      role = RbacRole.create!(account: account_user.account, name: 'Support')

      account_user.update!(rbac_role: role)
      expect(account_user.reload.rbac_managed).to be(true)

      account_user.update!(rbac_role: nil)
      expect(account_user.reload.rbac_role).to be_nil
      expect(account_user.rbac_managed).to be(true)
    end

    it 'rejects a role owned by another account' do
      role = RbacRole.create!(account: create(:account), name: 'Support')

      expect(account_user.update(rbac_role: role)).to be(false)
      expect(account_user.errors[:rbac_role]).to be_present
    end

    it 'rejects cross-account role references at the database boundary' do
      role = RbacRole.create!(account: create(:account), name: 'Support')

      expect do
        # Bypass model validation to exercise the composite tenant foreign key itself.
        # rubocop:disable Rails/SkipsModelValidations
        account_user.update_columns(rbac_role_id: role.id, rbac_managed: true)
        # rubocop:enable Rails/SkipsModelValidations
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'does not allow an RBAC-managed link to return to legacy mode' do
      account_user.update!(rbac_managed: true)

      expect(account_user.update(rbac_managed: false)).to be(false)
      expect(account_user.errors[:rbac_managed]).to be_present
    end

    it 'allows unrelated membership updates after an assigned role is deactivated' do
      role = RbacRole.create!(account: account_user.account, name: 'Support')
      account_user.update!(rbac_role: role)
      role.update!(active: false)

      expect(account_user.update(availability: :offline)).to be(true)
    end

    it 'does not allow a native administrator to receive an RBAC role' do
      administrator = create(:account_user, account: account_user.account, role: :administrator)
      role = RbacRole.create!(account: account_user.account, name: 'Support')

      expect(administrator.update(rbac_role: role)).to be(false)
      expect(administrator.errors[:rbac_role]).to be_present
    end
  end

  describe 'last administrator protection' do
    let(:administrator) { create(:account_user, account: account_user.account, role: :administrator) }

    it 'prevents demoting the last administrator' do
      expect(administrator.update(role: :agent)).to be(false)
      expect(administrator.errors[:role]).to include(I18n.t('errors.account_user.last_administrator'))
      expect(administrator.reload).to be_administrator
    end

    it 'prevents removing the last administrator' do
      expect { administrator.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)

      expect(described_class.exists?(administrator.id)).to be(true)
    end

    it 'allows demotion while another administrator remains' do
      create(:account_user, account: administrator.account, role: :administrator)

      expect(administrator.update!(role: :agent)).to be(true)
    end

    it 'allows removal while another administrator remains' do
      create(:account_user, account: administrator.account, role: :administrator)

      expect(administrator.destroy!).to be_destroyed
    end

    it 'protects the last administrator when destroy uses a stale agent instance' do
      promoted_agent = create(:account_user, account: administrator.account, role: :agent)
      stale_agent = described_class.find(promoted_agent.id)

      promoted_agent.update!(role: :administrator)
      administrator.update!(role: :agent)

      expect { stale_agent.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(promoted_agent.reload).to be_administrator
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end

  describe 'filtered unread count invalidation' do
    let(:account) { create(:account) }
    let(:user) { create(:user) }
    let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, user_visibility_changed!: true) }

    before do
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'invalidates filtered counts when the user is added to an account' do
      create(:account_user, account: account, user: user)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
    end

    it 'invalidates filtered counts when the user role changes' do
      account_user = create(:account_user, account: account, user: user)

      account_user.update!(role: :administrator)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id).twice
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        'account.cache_invalidated',
        kind_of(Time),
        account: account,
        cache_keys: account.cache_keys
      )
    end

    it 'invalidates filtered counts when the user is removed from an account' do
      account_user = create(:account_user, account: account, user: user)

      account_user.destroy!

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id).twice
    end
  end
end
