json.payload do
  if policy(@contact).show?
    json.partial! 'api/v1/accounts/contacts/contact', formats: [:json], resource: @contact, with_contact_inboxes: false
  else
    json.id @contact.id
  end
end
