# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactPolicy, type: :policy do
  subject(:contact_policy) { described_class }

  let(:account) { create(:account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :index?, :show?, :update? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :create? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  describe '#export?' do
    let(:managed_role) { RbacRole.create!(account: account, name: 'Managed export role') }
    let(:managed_account_user) { account.account_users.find_by!(user: agent) }
    let(:managed_context) { { user: agent, account: account, account_user: managed_account_user } }

    before do
      managed_account_user.update!(rbac_managed: true, rbac_role: managed_role)
    end

    it 'denies a managed agent with contacts.export but no contacts.read' do
      managed_role.role_permissions.create!(permission_key: 'contacts.export', scope_type: 'all_in_account')

      policy = described_class.new(managed_context, Contact)

      expect(policy.export?).to be(false)
    end

    it 'allows a managed agent with contacts.read and contacts.export' do
      %w[contacts.read contacts.export].each do |permission_key|
        managed_role.role_permissions.create!(permission_key: permission_key, scope_type: 'all_in_account')
      end

      policy = described_class.new(managed_context, Contact)

      expect(policy.export?).to be(true)
    end

    it 'preserves legacy administrator and agent behavior' do
      legacy_administrator = create(:user, :administrator, account: account)
      legacy_agent = create(:user, account: account, role: :agent)
      administrator_policy = described_class.new(
        { user: legacy_administrator, account: account,
          account_user: account.account_users.find_by!(user: legacy_administrator) },
        Contact
      )
      agent_policy = described_class.new(
        { user: legacy_agent, account: account, account_user: account.account_users.find_by!(user: legacy_agent) },
        Contact
      )

      expect(administrator_policy.export?).to be(true)
      expect(agent_policy.export?).to be(false)
    end
  end
end
