class Api::V1::Accounts::Contacts::ExportsController < Api::V1::Accounts::BaseController
  include Contacts::AuthenticatedBlobDownloads

  before_action :authorize_export!

  def show
    raise ActiveRecord::RecordNotFound unless Current.account.contacts_export.attached?

    stream_authenticated_blob(Current.account.contacts_export.blob, disposition: 'attachment')
  end

  private

  def authorize_export!
    authorize Contact, :export?
  end
end
