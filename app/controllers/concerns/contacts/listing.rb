module Contacts::Listing
  private

  def resolved_contacts
    return @resolved_contacts if @resolved_contacts

    @resolved_contacts = Current.account.contacts.resolved_contacts(use_crm_v2: Current.account.feature_enabled?('crm_v2'))
    @resolved_contacts = @resolved_contacts.tagged_with(params[:labels], any: true) if params[:labels].present?
    @resolved_contacts
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def fetch_contacts(contacts)
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    filtrate(contacts)
      .includes(includes_hash)
      .page(@current_page)
      .per(self.class::RESULTS_PER_PAGE)
  end

  def fetch_contacts_with_has_more(contacts)
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    offset = (@current_page.to_i - 1) * self.class::RESULTS_PER_PAGE
    results = filtrate(contacts)
              .includes(includes_hash)
              .offset(offset)
              .limit(self.class::RESULTS_PER_PAGE + 1)
              .to_a

    @has_more = results.size > self.class::RESULTS_PER_PAGE
    results = results.first(self.class::RESULTS_PER_PAGE) if @has_more
    @contacts_count = results.size
    results
  end

  def set_include_contact_inboxes
    @include_contact_inboxes = if params[:include_contact_inboxes].present?
                                 params[:include_contact_inboxes] == 'true'
                               else
                                 true
                               end
  end
end
