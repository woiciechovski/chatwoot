require 'rails_helper'

RSpec.describe RbacRolePermission do
  it 'does not accept a permission that is still planned' do
    role = RbacRole.create!(account: create(:account), name: 'Support')
    permission = described_class.new(
      rbac_role: role,
      permission_key: 'contacts.read',
      scope_type: 'all_in_account'
    )

    expect(permission).not_to be_valid
    expect(permission.errors[:permission_key]).to be_present
  end

  it 'rejects missing or unsupported scopes' do
    role = RbacRole.create!(account: create(:account), name: 'Support')
    permission = described_class.new(
      rbac_role: role,
      permission_key: 'contacts.read',
      scope_type: 'selected_inboxes'
    )

    expect(permission).not_to be_valid
    expect(permission.errors[:scope_type]).to be_present
  end
end
