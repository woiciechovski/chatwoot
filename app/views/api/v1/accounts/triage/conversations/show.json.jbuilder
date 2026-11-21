json.payload do
  json.execution do
    json.id @execution.id
    json.status @execution.status
    json.reserved_at @execution.reserved_at
    json.transferred_at @execution.transferred_at
    json.transferred_by_id @execution.transferred_by_id
    json.team_id @execution.team_id
    json.failure_message @execution.failure_message
    json.flow do
      json.id @execution.conversation_flow_id
      json.name @execution.conversation_flow.name
    end
  end
  json.conversation do
    json.partial! 'api/v1/conversations/partials/conversation', conversation: @execution.conversation
  end
end
