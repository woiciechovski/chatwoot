require 'rails_helper'

RSpec.describe Rbac::RoleManagementService do
  let(:account) { create(:account) }
  let(:admin) { create(:account_user, account: account, role: :administrator) }
  let(:service) { described_class.new(account: account, actor: admin) }

  describe '#create_role!' do
    it 'creates an account-owned role and records a sanitized audit event' do
      role = service.create_role!(name: 'Support', description: 'Customer support')

      expect(role).to have_attributes(account_id: account.id, name: 'Support', lock_version: 0)
      expect(RbacAuditEvent.last).to have_attributes(action: 'role.created', result: 'success', actor: admin)
      expect(RbacAuditEvent.last.details).to eq('name' => 'Support', 'changed_fields' => %w[name description])
    end
  end

  describe '#update_role!' do
    let!(:role) { RbacRole.create!(account: account, name: 'Support') }

    it 'requires the expected version and increments it on a successful update' do
      updated_role = service.update_role!(role_id: role.id, attributes: { name: 'Customer Support' }, expected_version: 0)

      expect(updated_role).to have_attributes(name: 'Customer Support', lock_version: 1)
      expect(RbacAuditEvent.last.action).to eq('role.updated')
      expect(RbacAuditEvent.last.details).to include(
        'changed_fields' => ['name'],
        'changed_values' => { 'name' => { 'from' => 'Support', 'to' => 'Customer Support' } }
      )
    end

    it 'rejects stale updates without changing the role' do
      expect do
        service.update_role!(role_id: role.id, attributes: { name: 'Customer Support' }, expected_version: 1)
      end.to raise_error(described_class::StaleVersionError)

      expect(role.reload.name).to eq('Support')
      expect(RbacAuditEvent.where(action: 'role.updated')).to be_empty
    end

    it 'does not expose roles owned by another account' do
      other_role = RbacRole.create!(account: create(:account), name: 'Support')

      expect do
        service.update_role!(role_id: other_role.id, attributes: { name: 'Changed' }, expected_version: 0)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'accepts integer and ASCII decimal-string versions' do
      service.update_role!(role_id: role.id, attributes: { name: 'Support N1' }, expected_version: 0)
      updated_role = service.update_role!(role_id: role.id, attributes: { name: 'Support N2' }, expected_version: '1')

      expect(updated_role).to have_attributes(name: 'Support N2', lock_version: 2)
    end

    it 'rejects versions with unsupported types, formats, or values without mutation' do
      invalid_versions = [1.0, 1.9, true, nil, '1.0', '1.9', 'text', -1, '-1', 2_147_483_648, '2147483648']

      invalid_versions.each do |expected_version|
        expect do
          service.update_role!(role_id: role.id, attributes: { name: 'Invalid Update' }, expected_version: expected_version)
        end.to raise_error(described_class::InvalidVersionError)
      end

      expect(role.reload).to have_attributes(name: 'Support', lock_version: 0)
      expect(RbacAuditEvent.where(action: 'role.updated')).to be_empty
    end

    it 'rolls back a role update when the success audit cannot be written' do
      allow(Rbac::AuditEvents::Recorder).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        service.update_role!(role_id: role.id, attributes: { name: 'Customer Support' }, expected_version: 0)
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(role.reload.name).to eq('Support')
    end
  end

  describe '#replace_grants!' do
    let!(:role) { RbacRole.create!(account: account, name: 'Support') }

    it 'accepts an empty replacement and records the change' do
      service.replace_grants!(role_id: role.id, grants: [], expected_version: 0)

      expect(role.reload.lock_version).to eq(1)
      expect(role.role_permissions).to be_empty
      expect(RbacAuditEvent.last.action).to eq('role.grants_replaced')
    end

    it 'rejects planned permissions without saving grants or audit events' do
      expect do
        service.replace_grants!(role_id: role.id, grants: [{ permission_key: 'companies.read', scope_type: 'all_in_account' }], expected_version: 0)
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(role.reload.role_permissions).to be_empty
      expect(RbacAuditEvent.where(action: 'role.grants_replaced')).to be_empty
    end
  end
end
