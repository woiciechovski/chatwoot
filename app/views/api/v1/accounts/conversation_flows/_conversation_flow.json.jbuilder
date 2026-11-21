json.id conversation_flow.id
json.name conversation_flow.name
json.description conversation_flow.description
json.enabled conversation_flow.enabled
json.created_by_id conversation_flow.created_by_id
json.updated_by_id conversation_flow.updated_by_id
json.created_at conversation_flow.created_at
json.updated_at conversation_flow.updated_at
json.inboxes do
  json.array! conversation_flow.inboxes do |inbox|
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
  end
end
