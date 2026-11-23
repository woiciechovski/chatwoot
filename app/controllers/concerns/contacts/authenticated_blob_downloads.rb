module Contacts::AuthenticatedBlobDownloads
  extend ActiveSupport::Concern

  private

  def stream_authenticated_blob(blob, disposition: 'inline')
    set_authenticated_blob_headers(blob, disposition)
    self.response_body = Enumerator.new do |stream|
      blob.download { |chunk| stream << chunk }
    end
  end

  def set_authenticated_blob_headers(blob, disposition)
    response.headers['Content-Type'] = blob.content_type
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(
      disposition: disposition, filename: blob.filename.to_s
    )
    response.headers['Content-Length'] = blob.byte_size.to_s
    response.headers['Last-Modified'] = blob.created_at.httpdate
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
