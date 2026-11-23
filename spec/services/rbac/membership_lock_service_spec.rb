require 'rails_helper'

RSpec.describe Rbac::MembershipLockService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let!(:membership) { create(:account_user, account: account, user: user, role: :administrator) }

  describe '.with_account' do
    it 'locks and yields the account for a coordinated account operation' do
      yielded_account = described_class.with_account(account_id: account.id) { |locked_account| locked_account }

      expect(yielded_account.id).to eq(account.id)
    end
  end

  describe '.with_membership' do
    it 'locks and yields the account, user, and current membership in order' do
      yielded_records = described_class.with_membership(
        account_id: account.id,
        user_id: user.id,
        membership_id: membership.id
      ) do |locked_account, locked_user, locked_membership|
        [locked_account, locked_user, locked_membership]
      end

      expect(yielded_records.map(&:id)).to eq([account.id, user.id, membership.id])
    end
  end

  describe '.with_user_memberships' do
    it 'yields all linked accounts in ascending ID order and their memberships' do
      other_account = create(:account)
      other_membership = create(:account_user, account: other_account, user: user)

      accounts, locked_user, memberships = described_class.with_user_memberships(user_id: user.id) do |locked_accounts, user_record, links|
        [locked_accounts, user_record, links]
      end

      expect(accounts.map(&:id)).to eq([account.id, other_account.id].sort)
      expect(locked_user.id).to eq(user.id)
      expect(memberships.map(&:id)).to contain_exactly(membership.id, other_membership.id)
    end

    it 'reuses the current lock scope for a nested callback' do
      yielded_membership = described_class.with_membership(
        account_id: account.id,
        user_id: user.id,
        membership_id: membership.id
      ) do
        described_class.with_membership(
          account_id: account.id,
          user_id: user.id,
          membership_id: membership.id
        ) { |_locked_account, _locked_user, locked_membership| locked_membership }
      end

      expect(yielded_membership.id).to eq(membership.id)
    end

    it 'rejects nested lock scope expansion before acquiring another account' do
      other_account = create(:account)
      other_membership = create(:account_user, account: other_account, user: user)

      expect do
        described_class.with_membership(account_id: account.id, user_id: user.id, membership_id: membership.id) do
          described_class.with_membership(
            account_id: other_account.id,
            user_id: user.id,
            membership_id: other_membership.id
          ) { flunk 'expanded scope should not be yielded' }
        end
      end.to raise_error(described_class::LockScopeExpansionError)
    end
  end
end
