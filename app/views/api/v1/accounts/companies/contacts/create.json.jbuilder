json.payload do
  if policy(@contact).show?
    json.partial! 'api/v1/accounts/companies/contacts/contact', formats: [:json], contact: @contact
  else
    json.id @contact.id
  end
end
