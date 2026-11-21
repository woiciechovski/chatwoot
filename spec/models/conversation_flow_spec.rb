require 'rails_helper'

RSpec.describe ConversationFlow do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account, role: :administrator) }

  describe 'validations' do
    it 'requires a name' do
      flow = described_class.new(account: account, created_by: creator, name: '')

      expect(flow).not_to be_valid
      expect(flow.errors[:name]).to be_present
    end
  end
end
