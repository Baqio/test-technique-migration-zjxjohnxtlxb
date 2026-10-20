class Importer::Base
  attr_reader :path, :report

  def initialize(path, report: MigrationReport.new)
    @path   = path
    @report = report
  end

  def call
    raise NotImplementedError
  end

  private

  def source
    File.basename(path)
  end

  def status_of(record)
    table = record.class.table_name

    return :"#{table}_created" if record.new_record?
    return :"#{table}_updated" if record.changed?

    :"#{table}_unchanged"
  end

  def report_update(record, locator)
    report.warn(
      source: source,
      locator: locator,
      message: "#{record.reference} mis à jour",
      changes: record.previous_changes.except("updated_at")
    )
  end

  def report_invalid(error, locator)
    report.error(
      source: source,
      locator: locator,
      message: error.record.errors.full_messages.join(", ")
    )
  end
end
