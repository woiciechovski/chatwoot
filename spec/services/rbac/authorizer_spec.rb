require 'rails_helper'

RSpec.describe Rbac::Authorizer do
  let(:account) { create(:account) }
  let(:agent) { create(:account_user, account: account, role: :agent) }
  let(:permission) { 'companies.read' }

  describe '.state_for' do
    it 'returns legacy when the account membership has never been RBAC-managed' do
      expect(described_class.state_for(account_user: agent, permission: permission)).to eq(:legacy)
    end

    it 'keeps RBAC-managed agents on legacy behavior while the module is planned' do
      role = RbacRole.create!(account: account, name: 'Support')
      agent.update!(rbac_role: role)

      expect(described_class.state_for(account_user: agent, permission: permission)).to eq(:legacy_for_unmigrated_domain)
    end

    it 'returns enforced RBAC for a managed membership in an enforced module' do
      role = RbacRole.create!(account: account, name: 'Support')
      agent.update!(rbac_role: role)
      allow(Rbac::Catalog).to receive(:find).with(permission).and_return(
        key: permission, module: 'contacts', status: 'enforced', assignable: true, scope_types: ['all_in_account']
      )

      expect(described_class.state_for(account_user: agent, permission: permission)).to eq(:enforced_rbac)
    end

    it 'enforces Contacts permissions from the real production catalog' do
      role = RbacRole.create!(account: account, name: 'Contacts reader')
      agent.update!(rbac_role: role)

      expect(described_class.state_for(account_user: agent, permission: 'contacts.read')).to eq(:enforced_rbac)
    end
  end

  describe '.allowed?' do
    it 'preserves legacy authorization for modules that have not migrated' do
      expect(described_class.allowed?(account_user: agent, permission: permission)).to be(true)
    end

    it 'denies an enforced permission when the RBAC-managed membership has no role' do
      agent.update!(rbac_managed: true)
      allow(Rbac::Catalog).to receive(:find).with(permission).and_return(
        key: permission, module: 'contacts', status: 'enforced', assignable: true, scope_types: ['all_in_account']
      )

      expect(described_class.allowed?(account_user: agent, permission: permission)).to be(false)
    end

    it 'denies Contacts access to a managed membership with no grant in the active catalog' do
      role = RbacRole.create!(account: account, name: 'Contacts role without grants')
      agent.update!(rbac_role: role)

      expect(described_class.allowed?(account_user: agent, permission: 'contacts.read')).to be(false)
    end

    it 'denies an enforced permission when the role has no explicit grant' do
      role = RbacRole.create!(account: account, name: 'Support')
      agent.update!(rbac_role: role)
      allow(Rbac::Catalog).to receive(:find).with(permission).and_return(
        key: permission, module: 'contacts', status: 'enforced', assignable: true, scope_types: ['all_in_account']
      )

      expect(described_class.allowed?(account_user: agent, permission: permission)).to be(false)
    end

    it 'allows a grant only for an active role and a resource in the same account' do
      role = RbacRole.create!(account: account, name: 'Support')
      agent.update!(rbac_role: role)
      allow(Rbac::Catalog).to receive(:find).with(permission).and_return(
        key: permission, module: 'contacts', status: 'enforced', assignable: true, scope_types: ['all_in_account']
      )
      allow(Rbac::Catalog).to receive(:assignable?).with(permission).and_return(true)
      allow(Rbac::Catalog).to receive(:scope_allowed?).with(permission, 'all_in_account').and_return(true)
      role.role_permissions.create!(permission_key: permission, scope_type: 'all_in_account')

      resource = instance_double(Company, account_id: account.id)
      other_resource = instance_double(Company, account_id: create(:account).id)

      expect(described_class.allowed?(account_user: agent, permission: permission, resource: resource)).to be(true)
      expect(described_class.allowed?(account_user: agent, permission: permission, resource: other_resource)).to be(false)

      role.update!(active: false)
      expect(described_class.allowed?(account_user: agent, permission: permission)).to be(false)
    end

    it 'denies unknown permissions and missing memberships' do
      expect(described_class.allowed?(account_user: agent, permission: 'contacts.admin')).to be(false)
      expect(described_class.allowed?(account_user: nil, permission: permission)).to be(false)
    end

    it 'keeps native administrators account-scoped and independent of custom roles' do
      administrator = create(:account_user, account: account, role: :administrator)

      expect(described_class.state_for(account_user: administrator, permission: permission)).to eq(:native_administrator)
      expect(described_class.allowed?(account_user: administrator, permission: permission)).to be(true)
      expect(described_class.allowed?(
               account_user: administrator,
               permission: permission,
               resource: instance_double(Company, account_id: create(:account).id)
             )).to be(false)
    end
  end
end
