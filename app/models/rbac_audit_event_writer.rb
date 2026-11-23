class RbacAuditEventWriter < RbacAuditEvent
  class << self
    def with_independent_connection(&)
      configure_independent_connection
      connection_pool.with_connection(&)
    end

    def committed_account?(account_id)
      account_query = Account.where(id: account_id).select(:id)
      connection.select_value(account_query.arel).present?
    end

    private

    def configure_independent_connection
      return if @independent_connection_configured

      (@independent_connection_mutex ||= Mutex.new).synchronize do
        return if @independent_connection_configured

        config = ActiveRecord::Base.connection_db_config.configuration_hash.dup
        config[:pool] = [ActiveRecord::Base.connection_pool.size, 2].min
        establish_connection(config)
        @independent_connection_configured = true
      end
    end
  end
end
