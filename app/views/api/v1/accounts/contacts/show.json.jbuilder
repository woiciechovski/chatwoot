json.payload do
  json.partial! 'api/v1/accounts/contacts/contact', formats: [:json], resource: @contact,
                with_contact_inboxes: @include_contact_inboxes
end
