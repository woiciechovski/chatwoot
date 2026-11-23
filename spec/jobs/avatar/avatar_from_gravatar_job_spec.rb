require 'rails_helper'

RSpec.describe Avatar::AvatarFromGravatarJob do
  let(:avatarable) { create(:contact) }
  let(:email) { 'test@test.com' }
  let(:gravatar_url) { "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}?d=404" }
  let(:avatar_admin) { create(:user, account: avatarable.account, role: :administrator) }
  let(:authorization) do
    Contacts::Authorization.user_avatar_context(
      account_user: avatarable.account.account_users.find_by!(user: avatar_admin),
      contact: avatarable,
      permission: 'contacts.update'
    )
  end

  it 'enqueues the job' do
    expect { described_class.perform_later(avatarable, email) }.to have_enqueued_job(described_class)
      .on_queue('purgable')
  end

  it 'will call AvatarFromUrlJob with gravatar url' do
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_later).with(avatarable, gravatar_url, authorization)
    described_class.perform_now(avatarable, email, authorization)
  end

  it 'will not call AvatarFromUrlJob if DISABLE_GRAVATAR is configured' do
    with_modified_env DISABLE_GRAVATAR: 'true' do
      expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later).with(avatarable, gravatar_url, authorization)
      described_class.perform_now(avatarable, '', authorization)
    end
  end

  it 'will not call AvatarFromUrlJob if email is blank' do
    expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later).with(avatarable, gravatar_url, authorization)
    described_class.perform_now(avatarable, '', authorization)
  end
end
