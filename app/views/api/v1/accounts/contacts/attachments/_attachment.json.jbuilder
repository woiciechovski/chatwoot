json.partial! 'api/v1/models/attachment', formats: [:json], attachment: attachment
if attachment.file.attached?
  download_path = api_v1_account_contact_attachment_download_path(
    account_id: Current.account.id,
    contact_id: contact_id,
    id: attachment.id
  )
  json.data_url download_path
  json.thumb_url(
    if attachment.image? && attachment.file.representable?
      "#{download_path}?thumbnail=true"
    else
      ''
    end
  )
else
  json.data_url ''
  json.thumb_url ''
end
