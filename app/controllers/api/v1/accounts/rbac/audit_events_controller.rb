class Api::V1::Accounts::Rbac::AuditEventsController < Api::V1::Accounts::Rbac::BaseController
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100

  def index
    events = Current.account.rbac_audit_events.order(created_at: :desc, id: :desc)
    events = events_before_cursor(events) if params[:before_id].present?
    limit = requested_limit
    page = events.limit(limit + 1).to_a
    has_more = page.length > limit
    page = page.first(limit)

    render json: {
      data: page.map { |event| serialize_event(event) },
      next_before_id: has_more ? page.last.id : nil
    }
  end

  private

  def events_before_cursor(events)
    cursor = Current.account.rbac_audit_events.find(params[:before_id])
    events.where(
      RbacAuditEvent.arel_table[:created_at].lt(cursor.created_at).or(
        RbacAuditEvent.arel_table[:created_at].eq(cursor.created_at).and(RbacAuditEvent.arel_table[:id].lt(cursor.id))
      )
    )
  end

  def requested_limit
    value = Integer(params.fetch(:limit, DEFAULT_LIMIT))
    value.clamp(1, MAX_LIMIT)
  rescue ArgumentError, TypeError
    DEFAULT_LIMIT
  end

  def serialize_event(event)
    {
      id: event.id,
      actor: { type: event.actor_type, id: event.actor_id },
      action: event.action,
      target: { type: event.target_type, id: event.target_id },
      result: event.result,
      details: event.details,
      request_id: event.request_id,
      created_at: event.created_at
    }
  end
end
