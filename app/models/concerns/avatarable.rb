# frozen_string_literal: true

module Avatarable
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers

  ALLOWED_AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  attr_accessor :avatar_authorization_context

  included do
    has_one_attached :avatar
    validate :acceptable_avatar, if: -> { avatar.changed? }
    after_save :fetch_avatar_from_gravatar
  end

  def avatar_url
    return url_for(avatar.representation(resize_to_fill: [250, nil])) if avatar.attached? && avatar.representable?

    ''
  end

  def authenticated_avatar_download_url
    return '' unless is_a?(Contact) && avatar.attached? && avatar.representable?

    avatar_download_api_v1_account_contact_path(account_id: account_id, id: id)
  end

  def fetch_avatar_from_gravatar
    return unless saved_changes.key?(:email)
    return if email.blank?

    authorization = contact_avatar_authorization_context
    return if is_a?(Contact) && authorization.blank?

    # Incase avatar_url is supplied, we don't want to fetch avatar from gravatar
    # So we will wait for it to be processed
    Avatar::AvatarFromGravatarJob.set(wait: 30.seconds).perform_later(self, email, authorization)
  end

  def acceptable_avatar
    return unless avatar.attached?

    errors.add(:avatar, 'is too big') if avatar.byte_size > 15.megabytes

    errors.add(:avatar, 'filetype not supported') unless ALLOWED_AVATAR_CONTENT_TYPES.include?(avatar.content_type)
  end

  private

  def contact_avatar_authorization_context
    return unless is_a?(Contact)

    context = avatar_authorization_context
    if context.blank?
      account_user = Current.account_user
      context = if account_user.is_a?(AccountUser) && account_user.account_id == account_id
                  Contacts::Authorization.user_avatar_context(
                    account_user: account_user,
                    contact: self,
                    permission: 'contacts.update'
                  )
                else
                  system_contact_avatar_context
                end
    end

    context&.to_h&.merge(principal_contact_id: id)
  end

  def system_contact_avatar_context
    contact_inbox = contact_inboxes.order(:id).first
    return if contact_inbox.blank?

    Contacts::Authorization.system_avatar_context(
      contact: self,
      inbox: contact_inbox.inbox,
      origin: 'contact_gravatar_callback'
    )
  end
end
