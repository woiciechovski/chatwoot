class CreateRbacCore < ActiveRecord::Migration[7.2]
  def change
    create_roles
    create_role_permissions
    create_audit_events
    add_account_user_role
  end

  private

  def create_roles
    create_table :rbac_roles do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :rbac_roles, [:account_id, :normalized_name], unique: true, name: 'index_rbac_roles_on_account_and_normalized_name'
    add_index :rbac_roles, [:account_id, :id], unique: true
  end

  def create_role_permissions
    create_table :rbac_role_permissions do |t|
      t.references :rbac_role, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :permission_key, null: false
      t.string :scope_type, null: false
      t.timestamps
    end

    add_index :rbac_role_permissions, [:rbac_role_id, :permission_key], unique: true, name: 'index_rbac_role_permissions_on_role_and_key'
  end

  def create_audit_events
    create_table :rbac_audit_events do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :actor_type, null: false
      t.bigint :actor_id
      t.string :action, null: false
      t.string :target_type, null: false
      t.bigint :target_id
      t.string :result, null: false, default: 'success'
      t.jsonb :details, null: false, default: {}
      t.string :request_id
      t.timestamps
    end

    add_index :rbac_audit_events, [:account_id, :created_at, :id], name: 'index_rbac_audit_events_for_account_history'
    add_index :rbac_audit_events, [:target_type, :target_id], name: 'index_rbac_audit_events_on_target'
  end

  def add_account_user_role
    add_reference :account_users, :rbac_role, index: false
    add_column :account_users, :rbac_managed, :boolean, null: false, default: false
    add_index :account_users, [:account_id, :rbac_role_id], name: 'index_account_users_on_account_and_rbac_role'
    add_foreign_key :account_users, :rbac_roles,
                    column: [:account_id, :rbac_role_id],
                    primary_key: [:account_id, :id],
                    name: 'fk_account_users_rbac_role_tenant',
                    on_delete: :restrict
  end
end
