class Rbac::AuditEvents::Recorder
  class MissingActorContextError < StandardError; end
  DENIED_EVENT_OPTIONS = %i[target_type target_id metadata system].freeze

  def self.record!(account:, actor:, action:, target:, metadata: {})
    raise MissingActorContextError, 'RBAC audit events require an explicit actor.' if actor.nil?

    RbacAuditEvent.create!(
      account: account,
      actor: actor,
      action: action,
      target_type: target.class.base_class.name,
      target_id: target.id,
      result: 'success',
      details: metadata.fetch(:details, {}),
      request_id: metadata[:request_id]
    )
  end

  def self.record_denied!(account:, actor:, action:, **options)
    unknown_options = options.keys - DENIED_EVENT_OPTIONS
    raise ArgumentError, "Unknown denied audit options: #{unknown_options.join(', ')}" if unknown_options.any?

    system = options.fetch(:system, false)
    raise MissingActorContextError, 'RBAC audit events require an explicit actor or system context.' if actor.nil? && !system

    attributes = denied_event_attributes(account, actor, action, options, system)
    return RbacAuditEvent.create!(attributes) unless ActiveRecord::Base.connection.open_transactions.positive?

    RbacAuditEventWriter.with_independent_connection do
      if RbacAuditEventWriter.committed_account?(account.id)
        RbacAuditEventWriter.create!(attributes)
      else
        RbacAuditEvent.create!(attributes)
      end
    end
  end

  def self.record_denied_safely!(**arguments)
    record_denied!(**arguments)
  rescue StandardError => e
    Rails.logger.error("RBAC denial audit failed: #{e.class}")
    nil
  end

  def self.denied_event_attributes(account, actor, action, options, system)
    metadata = options.fetch(:metadata, {})
    {
      account: account,
      actor_type: system ? 'System' : actor.class.base_class.name,
      actor_id: system ? nil : actor.id,
      action: action,
      target_type: options.fetch(:target_type, 'RbacRole'),
      target_id: options[:target_id],
      result: 'denied',
      details: {},
      request_id: metadata[:request_id]
    }
  end
  private_class_method :denied_event_attributes
end
