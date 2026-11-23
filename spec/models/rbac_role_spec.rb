require 'rails_helper'

RSpec.describe RbacRole do
  it 'normalizes role names and keeps uniqueness within an account' do
    account = create(:account)
    first_role = described_class.create!(account: account, name: '  Support  ')
    duplicate_role = described_class.new(account: account, name: 'support')

    expect(first_role.normalized_name).to eq('support')
    expect(duplicate_role).not_to be_valid
    expect(duplicate_role.errors[:name]).to be_present
  end

  it 'allows the same normalized name in another account' do
    first_account = create(:account)
    second_account = create(:account)

    first_role = described_class.create!(account: first_account, name: 'Support')
    second_role = described_class.create!(account: second_account, name: 'support')

    expect(second_role).to be_persisted
    expect(first_role.normalized_name).to eq(second_role.normalized_name)
  end

  it 'starts active at version zero' do
    role = described_class.create!(account: create(:account), name: 'Support')

    expect(role).to be_active
    expect(role.lock_version).to eq(0)
  end
end
