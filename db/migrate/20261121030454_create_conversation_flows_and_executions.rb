class CreateConversationFlowsAndExecutions < ActiveRecord::Migration[7.2]
  def change
    create_conversation_flows
    add_conversation_flow_to_inboxes
    create_conversation_flow_executions
  end

  private

  def create_conversation_flows
    create_table :conversation_flows do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :conversation_flows, [:account_id, :enabled, :id]
  end

  def add_conversation_flow_to_inboxes
    add_reference :inboxes, :conversation_flow, foreign_key: { on_delete: :nullify }
  end

  def create_conversation_flow_executions
    create_table :conversation_flow_executions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation_flow, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: 'reserved'
      t.datetime :reserved_at, null: false
      t.datetime :transferred_at
      t.references :transferred_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :team, foreign_key: { on_delete: :nullify }
      t.text :failure_message
      t.datetime :failed_at
      t.timestamps
    end

    add_index :conversation_flow_executions, [:account_id, :status, :reserved_at, :id],
              name: 'index_conversation_flow_executions_for_triage'
  end
end
