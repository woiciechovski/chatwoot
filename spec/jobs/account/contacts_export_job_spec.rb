require 'rails_helper'

RSpec.describe Account::ContactsExportJob do
  subject(:job) { described_class.perform_later(account.id, user.id, [], {}) }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account, email: 'account-user-test@test.com') }

  let(:email_filter) do
    {
      :attribute_key => 'email',
      :filter_operator => 'contains',
      :values => 'looped',
      :query_operator => 'and',
      :attribute_model => 'standard',
      :custom_attribute_type => ''
    }
  end

  let(:city_filter) do
    {
      :attribute_key => 'country_code',
      :filter_operator => 'equal_to',
      :values => ['India'],
      :query_operator => 'and',
      :attribute_model => 'standard',
      :custom_attribute_type => ''
    }
  end

  let(:single_filter) do
    {
      :payload => [email_filter.merge(:query_operator => nil)]
    }
  end

  let(:multiple_filters) do
    {
      :payload => [city_filter, email_filter.merge(:query_operator => nil)]
    }
  end

  def manage_user_with_permissions(account, user, *permission_keys)
    role = RbacRole.create!(account: account, name: "Contacts export #{SecureRandom.hex(4)}")
    permission_keys.each do |permission_key|
      role.role_permissions.create!(permission_key: permission_key, scope_type: 'all_in_account')
    end
    account.account_users.find_by!(user: user).update!(rbac_managed: true, rbac_role: role)
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  it 'does not process an export for a managed agent with contacts.export but no contacts.read' do
    managed_agent = create(:user, account: account, role: :agent, email: 'managed-export@test.com')
    manage_user_with_permissions(account, managed_agent, 'contacts.export')
    create(:contact, account: account, email: 'must-not-export@example.com')

    described_class.perform_now(account.id, managed_agent.id, %w[id email], {})

    expect(account.contacts_export).not_to be_attached
  end

  it 'processes an export for a managed agent with contacts.read and contacts.export' do
    managed_agent = create(:user, account: account, role: :agent, email: 'managed-export@test.com')
    manage_user_with_permissions(account, managed_agent, 'contacts.read', 'contacts.export')
    create(:contact, account: account, email: 'authorized-export@example.com')

    described_class.perform_now(account.id, managed_agent.id, %w[id email], {})

    csv_content = account.contacts_export.download.force_encoding('UTF-8')

    expect(account.contacts_export).to be_attached
    expect(csv_content).to include('authorized-export@example.com')
  end

  it 'rechecks contacts.read in the worker after it is revoked' do
    managed_agent = create(:user, account: account, role: :agent, email: 'managed-export@test.com')
    manage_user_with_permissions(account, managed_agent, 'contacts.read', 'contacts.export')
    role = account.account_users.find_by!(user: managed_agent).rbac_role
    role.role_permissions.find_by!(permission_key: 'contacts.read').destroy!
    create(:contact, account: account, email: 'revoked-read@example.com')

    described_class.perform_now(account.id, managed_agent.id, %w[id email], {})

    expect(account.contacts_export).not_to be_attached
  end

  context 'when export_contacts' do
    before do
      create(:contact, account: account, phone_number: '+910808080818', email: 'test1@text.example')
      4.times do |i|
        create(:contact, account: account, email: "looped-#{i + 3}@text.example.com")
      end
      4.times do |i|
        create(:contact, account: account, additional_attributes: { :country_code => 'India' }, email: "looped-#{i + 10}@text.example.com")
      end
      create(:contact, account: account, phone_number: '+910808080808', email: 'test2@text.example')
    end

    it 'generates CSV file and attach to account' do
      mailer = double
      allow(AdministratorNotifications::AccountNotificationMailer).to receive(:with).with(account: account).and_return(mailer)
      allow(mailer).to receive(:contact_export_complete)

      described_class.perform_now(account.id, user.id, [], {})

      file_url = Rails.application.routes.url_helpers.export_download_api_v1_account_contacts_url(
        account_id: account.id
      )

      expect(account.contacts_export).to be_present
      expect(file_url).to include("/api/v1/accounts/#{account.id}/contacts/export/download")
      expect(mailer).to have_received(:contact_export_complete).with(file_url, user.email)
    end

    it 'stops before the next batch and does not publish the export after permission revocation' do
      101.times { |index| create(:contact, account: account, email: "batch-#{index}@text.example") }
      allow(Contacts::Authorization).to receive(:allowed?).and_return(true, true, false)
      mailer = double
      allow(AdministratorNotifications::AccountNotificationMailer).to receive(:with).and_return(mailer)
      allow(mailer).to receive(:contact_export_complete)

      described_class.perform_now(account.id, user.id, %w[id email], {})

      expect(account.contacts_export).not_to be_attached
      expect(mailer).not_to have_received(:contact_export_complete)
    end

    it 'does not export after its account membership is removed' do
      create(:user, :administrator, account: account)
      account.account_users.find_by!(user: user).destroy!

      described_class.perform_now(account.id, user.id, %w[id email], {})

      expect(account.contacts_export).not_to be_attached
    end

    it 'generates valid data export file' do
      described_class.perform_now(account.id, user.id, %w[id name email phone_number column_not_present], {})

      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      emails = csv_data.pluck('email')
      phone_numbers = csv_data.pluck('phone_number')

      expect(csv_data.length).to eq(account.contacts.count)

      expect(emails).to include('test1@text.example', 'test2@text.example')
      # Phone numbers lead with "+" (a formula character), so they are prefixed with "'" on export.
      expect(phone_numbers).to include("'+910808080818", "'+910808080808")
    end

    it 'neutralises formula-leading characters in exported values' do
      create(:contact, account: account, name: '=HYPERLINK("http://evil.example")', email: 'formula@text.example')

      described_class.perform_now(account.id, user.id, %w[id name email], {})

      csv_content = account.contacts_export.download.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
      csv_data = CSV.parse(csv_content, headers: true)
      row = csv_data.find { |r| r['email'] == 'formula@text.example' }

      expect(row['name']).to start_with("'")
    end

    it 'exports labels when requested through column names' do
      contact_with_labels = account.contacts.first
      create(:label, account: account, title: 'vip')
      contact_with_labels.add_labels(%w[vip])

      described_class.perform_now(account.id, user.id, %w[id email labels], {})

      csv_content = account.contacts_export.download.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
      csv_data = CSV.parse(csv_content, headers: true)
      row = csv_data.find { |r| r['email'] == contact_with_labels.email }

      expect(csv_data.headers).to eq(%w[id email labels])
      expect(row['labels']).to eq('vip')
    end

    it 'bulk loads labels while exporting contacts' do
      create(:label, account: account, title: 'vip')
      create(:label, account: account, title: 'support')
      account.contacts.find_each { |contact| contact.add_labels(%w[vip support]) }
      account.contacts.first.add_labels('legacy_tag')

      taggings_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _started, _finished, _unique_id, payload|
        taggings_queries << payload[:sql] if payload[:sql].include?('FROM "taggings"')
      end

      described_class.perform_now(account.id, user.id, [], {})
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      row = csv_data.find { |r| r['email'] == account.contacts.first.email }

      expect(csv_data.headers).to include('labels')
      expect(row['labels'].split(described_class::LABELS_DELIMITER)).to match_array(%w[vip support])
      expect(taggings_queries.size).to eq(1)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it 'prepends UTF-8 BOM to the exported CSV for spreadsheet compatibility' do
      described_class.perform_now(account.id, user.id, [], {})

      raw = account.contacts_export.download
      expect(raw.bytes[0..2]).to eq([0xEF, 0xBB, 0xBF])
    end

    it 'returns all resolved contacts as results when filter is not prvoided' do
      create(:contact, account: account, email: nil, phone_number: nil)
      described_class.perform_now(account.id, user.id, %w[id name email column_not_present], {})
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      expect(csv_data.length).to eq(account.contacts.resolved_contacts.count)
    end

    it 'returns resolved contacts filtered if labels are provided' do
      # Adding label to a resolved contact
      Contact.last.add_labels(['spec-billing'])
      contact = create(:contact, account: account, email: nil, phone_number: nil)
      contact.add_labels(['spec-billing'])
      described_class.perform_now(account.id, user.id, [], { :payload => nil, :label => 'spec-billing' })
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      # since there is only 1 resolved contact with 'spec-billing' label
      expect(csv_data.length).to eq(1)
    end

    it 'returns filtered data limited to resolved contacts when filter is provided' do
      create(:contact, account: account, email: nil, phone_number: nil, additional_attributes: { :country_code => 'India' })
      described_class.perform_now(account.id, user.id, [], { :payload => [city_filter.merge(:query_operator => nil)] }.with_indifferent_access)
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      expect(csv_data.length).to eq(4)
    end

    it 'returns filtered data when multiple filters are provided' do
      described_class.perform_now(account.id, user.id, [], multiple_filters.with_indifferent_access)
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      # since there are only 4 contacts with 'looped' in email and 'India' as country_code
      expect(csv_data.length).to eq(4)
    end

    it 'returns filtered data when a single filter is provided' do
      described_class.perform_now(account.id, user.id, [], single_filter.with_indifferent_access)
      csv_data = CSV.parse(account.contacts_export.download, headers: true)
      # since there are only 8 contacts with 'looped' in email
      expect(csv_data.length).to eq(8)
    end
  end
end
