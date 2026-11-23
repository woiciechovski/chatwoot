module DataImports::ConversationsPageJob
  def perform(data_import, starting_after = nil, run_id = nil)
    return if skip_import?(data_import, run_id)
    return fail_import!(Pundit::NotAuthorizedError.new('Data import authorization is no longer valid')) unless
      DataImports::Authorization.new(data_import).allowed_to_run?

    importer = importer_for(data_import, run_id)
    return importer.finish! if importer.conversations_completed?

    result = importer.import_conversations_page(starting_after: starting_after)
    return if skip_import?(data_import, run_id)
    return self.class.perform_later(data_import, result.next_cursor, run_id) unless result.done?

    importer.finish!
  rescue StandardError => e
    fail_unexpected_error(importer, e)
  end
end
