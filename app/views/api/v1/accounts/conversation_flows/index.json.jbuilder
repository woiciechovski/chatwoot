json.payload do
  json.array! @conversation_flows do |conversation_flow|
    json.partial! 'api/v1/accounts/conversation_flows/conversation_flow', conversation_flow: conversation_flow
  end
end
