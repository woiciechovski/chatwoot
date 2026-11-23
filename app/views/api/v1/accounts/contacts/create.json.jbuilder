json.payload do
  json.contact do
    if policy(@contact).show?
      json.partial! 'api/v1/accounts/contacts/contact', formats: [:json], resource: @contact, with_contact_inboxes: true
    else
      json.id @contact.id
    end
  end
  if policy(@contact).show?
    json.contact_inbox do
      json.inbox @contact_inbox&.inbox
      json.source_id @contact_inbox&.source_id
    end
  end
end
