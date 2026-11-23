json.partial! 'api/v1/models/contact', formats: [:json], resource: resource, with_contact_inboxes: with_contact_inboxes
json.thumbnail(
  if resource.avatar.attached? && resource.avatar.representable?
    avatar_download_api_v1_account_contact_path(account_id: Current.account.id, id: resource.id)
  else
    ''
  end
)
