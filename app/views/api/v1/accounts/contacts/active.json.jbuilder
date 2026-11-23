json.meta do
  json.count @contacts_count
  json.current_page @current_page
end

json.payload do
  json.array! @contacts do |contact|
    json.partial! 'api/v1/accounts/contacts/contact', formats: [:json], resource: contact,
                  with_contact_inboxes: @include_contact_inboxes
  end
end
