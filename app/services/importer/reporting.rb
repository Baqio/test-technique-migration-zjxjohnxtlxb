module Importer::Reporting
  private

  def report_warning(key, locator, message)
    report.count(key)
    report.warn(source: source, locator: locator, message: message)
  end

  def report_error(key, locator, message)
    report.count(key)
    report.error(source: source, locator: locator, message: message)
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
