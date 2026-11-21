json.data do
  json.meta do
    json.current_page @executions.current_page
    json.total_pages @executions.total_pages
    json.total_count @executions.total_count
  end
  json.payload do
    json.array! @executions do |execution|
      json.execution do
        json.id execution.id
        json.status execution.status
        json.reserved_at execution.reserved_at
        json.flow do
          json.id execution.conversation_flow_id
          json.name execution.conversation_flow.name
        end
      end
      json.conversation do
        json.partial! 'api/v1/conversations/partials/conversation', conversation: execution.conversation
      end
    end
  end
end
