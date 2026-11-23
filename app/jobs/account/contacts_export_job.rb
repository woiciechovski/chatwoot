class Account::ContactsExportJob < ApplicationJob
  queue_as :low

  LABELS_COLUMN = 'labels'.freeze
  LABELS_DELIMITER = ','.freeze
  BATCH_SIZE = 100

  def perform(account_id, user_id, column_names, params)
    @account = Account.find(account_id)
    @params = params
    @account_user = @account.account_users.includes(:user).find_by(user_id: user_id)
    return unless @account_user
    return unless export_authorized?

    headers = valid_headers(column_names)
    csv_data = generate_csv(headers)
    return unless csv_data
    return unless export_authorized?

    attach_export_file(csv_data)
    return unless export_authorized?

    send_mail
  end

  private

  def generate_csv(headers)
    authorized = true
    csv_data = CSVSafe.generate do |csv|
      csv << headers
      contacts.in_batches(of: BATCH_SIZE, load: true, error_on_ignore: false) do |batch|
        unless export_authorized?
          authorized = false
          break
        end

        batch_contacts = batch.to_a
        preload_contact_labels(batch_contacts) if headers.include?(LABELS_COLUMN)
        batch_contacts.each do |contact|
          csv << headers.map { |header| value_for_header(contact, header) }
        end
      end
    end

    csv_data if authorized && export_authorized?
  end

  def value_for_header(contact, header)
    return contact_labels_by_id.fetch(contact.id, []).join(LABELS_DELIMITER) if header == LABELS_COLUMN

    contact.send(header)
  end

  def approved_labels
    @approved_labels ||= @account.labels.pluck(:title)
  end

  def preload_contact_labels(contacts_to_export)
    contact_ids = contacts_to_export.map(&:id)
    return if contact_ids.blank?

    ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(context: LABELS_COLUMN, taggable_type: 'Contact', taggable_id: contact_ids)
      .where(tags: { name: approved_labels })
      .pluck(:taggable_id, 'tags.name')
      .each { |contact_id, label| contact_labels_by_id[contact_id] << label }
  end

  def contact_labels_by_id
    @contact_labels_by_id ||= Hash.new { |hash, contact_id| hash[contact_id] = [] }
  end

  def contacts
    if @params.present? && @params[:payload].present? && @params[:payload].any?
      result = ::Contacts::FilterService.new(@account, @account_user, @params).perform
      result[:contacts]
    elsif @params[:label].present?
      @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2')).tagged_with(@params[:label], any: true)
    else
      @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
    end
  end

  def valid_headers(column_names)
    requested_headers = column_names.presence || default_columns

    # Keep requested header order while allowing the virtual labels column.
    requested_headers.select do |header|
      header == LABELS_COLUMN || Contact.column_names.include?(header)
    end.uniq
  end

  def attach_export_file(csv_data)
    return if csv_data.blank?

    # Prepend UTF-8 BOM so that spreadsheet applications (e.g. Excel)
    # correctly recognise the file encoding for non-ASCII characters
    # such as Arabic, Japanese, and Chinese.
    bom = "\xEF\xBB\xBF"

    @account.contacts_export.attach(
      io: StringIO.new("#{bom}#{csv_data}"),
      filename: "#{@account.name}_#{@account.id}_contacts.csv",
      content_type: 'text/csv'
    )
  end

  def send_mail
    file_url = account_contact_export_url
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.contact_export_complete(file_url, @account_user.user.email)&.deliver_later
  end

  def account_contact_export_url
    Rails.application.routes.url_helpers.export_download_api_v1_account_contacts_url(account_id: @account.id)
  end

  def export_authorized?
    Contacts::Authorization.allowed?(account: @account, user_id: @account_user.user_id, permission: 'contacts.export')
  end

  def default_columns
    %w[id name email phone_number labels]
  end
end
