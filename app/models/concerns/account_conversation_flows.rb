module AccountConversationFlows
  extend ActiveSupport::Concern

  included do
    has_many :conversations, dependent: :destroy_async
    has_many :conversation_flows, dependent: :destroy_async
    has_many :conversation_flow_executions, dependent: :destroy_async
  end
end
