class Rbac::AuditEvents::RoleChanges
  def self.for_update(role, attributes)
    changed_fields = attributes.keys.map(&:to_s).select { |attribute| role.saved_changes.key?(attribute) }
    changed_values = changed_fields.each_with_object({}) do |attribute, safe_changes|
      next unless %w[name active].include?(attribute)

      previous_value, current_value = role.saved_changes.fetch(attribute)
      safe_changes[attribute] = { from: previous_value, to: current_value }
    end

    {
      changed_fields: changed_fields,
      changed_values: changed_values
    }
  end

  def self.for_grants(previous_grants, grants)
    current_grants = grants.map do |grant|
      grant.to_h.symbolize_keys.slice(:permission_key, :scope_type).transform_keys(&:to_s)
    end
    previous_by_key = previous_grants.index_by { |grant| grant[:permission_key] }
    current_by_key = current_grants.index_by { |grant| grant['permission_key'] }

    {
      added: (current_by_key.keys - previous_by_key.keys).sort,
      removed: (previous_by_key.keys - current_by_key.keys).sort,
      changed_scopes: changed_scopes(previous_by_key, current_by_key)
    }
  end

  def self.changed_scopes(previous_by_key, current_by_key)
    (current_by_key.keys & previous_by_key.keys).filter_map do |key|
      previous_scope = previous_by_key.fetch(key)[:scope_type]
      current_scope = current_by_key.fetch(key)['scope_type']
      next if current_scope == previous_scope

      { permission_key: key, from: previous_scope, to: current_scope }
    end
  end

  private_class_method :changed_scopes
end
