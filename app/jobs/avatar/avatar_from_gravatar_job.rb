class Avatar::AvatarFromGravatarJob < ApplicationJob
  queue_as :purgable

  def perform(avatarable, email, authorization = nil)
    authorization = authorization.to_h.with_indifferent_access if authorization.present?
    return if GlobalConfigService.load('DISABLE_GRAVATAR', '').present?
    return if email.blank?
    return if avatarable.avatar_url.present?
    return if avatarable.is_a?(Contact) && !contact_avatar_authorized?(avatarable, authorization)

    hash = Digest::MD5.hexdigest(email)
    gravatar_url = "https://www.gravatar.com/avatar/#{hash}?d=404"
    Avatar::AvatarFromUrlJob.perform_later(avatarable, gravatar_url, authorization)
  end

  private

  def contact_avatar_authorized?(contact, authorization)
    return false if authorization.blank?

    Contacts::Authorization.new(account: contact.account, user_id: authorization[:user_id]).avatar_allowed?(contact, authorization)
  end
end
