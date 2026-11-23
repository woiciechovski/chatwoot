class Rbac::Catalog
  ENTRIES = [
    { key: 'contacts.read', module: 'contacts', action: 'read', description: 'View contacts in the account.', status: 'enforced', assignable: true,
      scope_types: ['all_in_account'] },
    { key: 'contacts.create', module: 'contacts', action: 'create', description: 'Create contacts in the account.', status: 'enforced',
      assignable: true, scope_types: ['all_in_account'] },
    { key: 'contacts.update', module: 'contacts', action: 'update', description: 'Update contacts in the account.', status: 'enforced',
      assignable: true, scope_types: ['all_in_account'] },
    { key: 'contacts.delete', module: 'contacts', action: 'delete', description: 'Delete contacts in the account.', status: 'enforced',
      assignable: true, scope_types: ['all_in_account'] },
    { key: 'contacts.import', module: 'contacts', action: 'import', description: 'Import contacts into the account.', status: 'enforced',
      assignable: true, scope_types: ['all_in_account'] },
    { key: 'contacts.export', module: 'contacts', action: 'export', description: 'Export contacts from the account.', status: 'enforced',
      assignable: true, scope_types: ['all_in_account'] },
    { key: 'companies.read', module: 'companies', action: 'read', description: 'View companies in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'companies.create', module: 'companies', action: 'create', description: 'Create companies in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'companies.update', module: 'companies', action: 'update', description: 'Update companies in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'companies.delete', module: 'companies', action: 'delete', description: 'Delete companies in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'reports.read', module: 'reports', action: 'read', description: 'View report data for the account.', status: 'planned', assignable: false,
      scope_types: ['all_in_account'] },
    { key: 'reports.export', module: 'reports', action: 'export', description: 'Export report data for the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'knowledge_base.read', module: 'knowledge_base', action: 'read', description: 'View knowledge base content in the account.',
      status: 'planned', assignable: false, scope_types: ['all_in_account'] },
    { key: 'knowledge_base.create', module: 'knowledge_base', action: 'create',
      description: 'Create knowledge base content in the account.', status: 'planned', assignable: false,
      scope_types: ['all_in_account'] },
    { key: 'knowledge_base.update', module: 'knowledge_base', action: 'update',
      description: 'Update knowledge base content in the account.', status: 'planned', assignable: false,
      scope_types: ['all_in_account'] },
    { key: 'knowledge_base.delete', module: 'knowledge_base', action: 'delete',
      description: 'Delete knowledge base content in the account.', status: 'planned', assignable: false,
      scope_types: ['all_in_account'] },
    { key: 'knowledge_base.publish', module: 'knowledge_base', action: 'publish',
      description: 'Publish knowledge base content.', status: 'planned', assignable: false,
      scope_types: ['all_in_account'] },
    { key: 'campaigns.read', module: 'campaigns', action: 'read', description: 'View campaigns in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'campaigns.create', module: 'campaigns', action: 'create', description: 'Create campaigns in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'campaigns.update', module: 'campaigns', action: 'update', description: 'Update campaigns and their scheduling settings.',
      status: 'planned', assignable: false, scope_types: ['all_in_account'] },
    { key: 'campaigns.delete', module: 'campaigns', action: 'delete', description: 'Delete campaigns in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'flows.read', module: 'flows', action: 'read', description: 'View conversation flows in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'flows.create', module: 'flows', action: 'create', description: 'Create conversation flows in the account.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'flows.update', module: 'flows', action: 'update', description: 'Update conversation flow definitions.', status: 'planned',
      assignable: false, scope_types: ['all_in_account'] },
    { key: 'flows.manage_inboxes', module: 'flows', action: 'manage_inboxes', description: 'Manage inbox assignments for conversation flows.',
      status: 'planned', assignable: false, scope_types: ['all_in_account'] },
    { key: 'triage.read', module: 'triage', action: 'read', description: 'View the triage queue and its conversations.', status: 'planned',
      assignable: false, scope_types: [] },
    { key: 'triage.transfer', module: 'triage', action: 'transfer', description: 'Transfer triage conversations to an authorized team.',
      status: 'planned', assignable: false, scope_types: [] }
  ].map do |entry|
    entry.each_value do |value|
      value.is_a?(Array) ? value.each(&:freeze).freeze : value.freeze
    end
    entry.freeze
  end.freeze

  def self.entries
    ENTRIES
  end

  def self.find(permission_key)
    ENTRIES.find { |entry| entry[:key] == permission_key }
  end

  def self.assignable?(permission_key)
    entry = find(permission_key)
    entry.present? && entry[:status] == 'enforced' && entry[:assignable]
  end

  def self.assignable_keys
    ENTRIES.select { |entry| assignable?(entry[:key]) }.pluck(:key)
  end

  def self.scope_allowed?(permission_key, scope_type)
    entry = find(permission_key)
    entry.present? && assignable?(permission_key) && entry[:scope_types].include?(scope_type)
  end
end
