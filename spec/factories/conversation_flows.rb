FactoryBot.define do
  factory :conversation_flow do
    account
    created_by { create(:user, account: account, role: :administrator) }
    sequence(:name) { |number| "Conversation flow #{number}" }
    enabled { false }
  end
end
