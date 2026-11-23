class DataImports::CsvFile
  def initialize(data_import)
    @data_import = data_import
  end

  def each_row(&)
    with_import_file do |file|
      csv_reader(file).each(&)
    end
  end

  def headers
    with_import_file do |file|
      csv_reader(file).first&.headers || []
    end
  end

  private

  def csv_reader(file)
    file.rewind
    raw_data = file.read
    utf8_data = raw_data.force_encoding('UTF-8')
    clean_data = utf8_data.valid_encoding? ? utf8_data : utf8_data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
    clean_data = clean_data.delete_prefix("\xEF\xBB\xBF")

    CSV.new(StringIO.new(clean_data), headers: true)
  end

  def with_import_file
    temp_dir = Rails.root.join('tmp/imports')
    FileUtils.mkdir_p(temp_dir)

    @data_import.import_file.open(tmpdir: temp_dir) do |file|
      file.binmode
      yield file
    end
  end
end
