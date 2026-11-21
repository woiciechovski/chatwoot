class AddAgentConversationAccessToInboxes < ActiveRecord::Migration[7.2]
  def change
    add_column :inboxes, :agent_conversation_access, :string, default: 'all', null: false
  end
end
