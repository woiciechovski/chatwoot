module Contacts::CompanyAssociationAuthorization
  private

  def authorize_contact_company_changes!(contact = @contact, creating: false)
    return unless Current.account.feature_enabled?('companies')

    authorize_explicit_company_change!(contact) unless creating
    authorize_legacy_company_association!(contact) if params[:resolve_legacy_company].to_s == 'true'
    authorize_email_company_association!(contact, creating: creating)
  end

  def authorize_explicit_company_change!(contact)
    return unless params.key?(:company_id)

    new_company = Current.account.companies.find(permitted_params[:company_id]) if permitted_params[:company_id].present?
    authorize_company_update!(contact.company_id) if contact.company_id.present? && contact.company_id != new_company&.id
    authorize new_company, :update? if new_company
  end

  def authorize_company_update!(company_id)
    authorize Current.account.companies.find(company_id), :update?
  end

  def authorize_legacy_company_association!(contact)
    return if contact.company_id.present?

    company_name = contact_additional_attributes['company_name'].to_s.strip
    return if company_name.blank? || company_name.length > Limits::COMPANY_NAME_LENGTH_LIMIT

    existing_company = Current.account.companies.where('LOWER(name) = ?', company_name.downcase).first
    authorize_company_association!(existing_company)
  end

  def authorize_email_company_association!(contact, creating:)
    return if params.key?(:company_id) || contact.company_id.present?

    candidate_email = if creating
                        permitted_params[:email]
                      elsif contact.email.blank?
                        contact_update_params[:email]
                      end
    return if candidate_email.blank?
    return unless Companies::BusinessEmailDetectorService.new(candidate_email).perform

    domain = candidate_email.split('@').last.downcase
    existing_company = Current.account.companies.find_by(domain: domain)
    authorize_company_association!(existing_company)
  end

  def authorize_company_association!(company)
    if company
      authorize company, :update?
    else
      authorize Company, :create?
    end
  end
end
