class Importer::Base
  include Importer::Reporting

  attr_reader :path, :report

  def initialize(
    path, report: MigrationReport.new(title: "Reprise : #{File.basename(path)}")
  )
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
end
