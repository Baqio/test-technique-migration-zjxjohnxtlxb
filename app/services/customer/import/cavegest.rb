class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  REQUIRED_HEADERS = ["Code", "Nom", "Libellé", "Adresse", "Code postal", "Ville", "Pays"].freeze

  def initialize(path, sheets:, **options)
    super(path, **options)
    @sheets = Array(sheets)
  end

  def call
    report_sheets_left_aside

    (@sheets & workbook.sheets).each { |name| import_sheet(name) }

    report
  end

  private

  def workbook
    @workbook ||= Roo::Excelx.new(path)
  end

  def import_sheet(name)
    sheet  = workbook.sheet(name)
    header = header_line_of(sheet)

    if header.nil?
      return report_error(
        :headers_not_found,
        "feuille « #{name} »",
        "aucune ligne portant les colonnes attendues : #{REQUIRED_HEADERS.join(', ')}"
      )
    end

    map = Importer::HeaderMap.new(sheet.row(header))

    ((header + 1)..sheet.last_row).each do |line|
      row = Importer::Row.new(sheet.row(line), "#{name} ligne #{line}", map)

      import_customer(row) if record?(row)
    end
  rescue IndexError => error
    report_error(:headers_not_found, "feuille « #{name} »", error.message)
  end

  def header_line_of(sheet)
    (1..sheet.last_row).find { |line| (REQUIRED_HEADERS - sheet.row(line)).empty? }
  end

  def report_sheets_left_aside
    (workbook.sheets - @sheets).each do |name|
      sheet  = workbook.sheet(name)
      banner = N.text(sheet.row(1).first)

      report_warning(
        :sheets_left_aside,
        "feuille « #{name} »",
        ["non reprise (#{sheet.last_row} lignes)", banner].compact.join(" : ")
      )
    end

    (@sheets - workbook.sheets).each do |name|
      report_error(
        :sheets_not_found,
        "feuille « #{name} »",
        "absente du fichier, qui contient : #{workbook.sheets.join(', ')}"
      )
    end
  end

  def record?(row)
    code = N.text(row.value("Code", 0))
    !code.nil? && !code.upcase.start_with?("TOTAL")
  end

  def import_customer(row)
    reference  = N.text(row.value("Code", 0))
    attributes = attributes_for(row)

    return report_duplicate(row, reference, attributes) if seen.key?(reference)

    seen[reference] = attributes.hash

    customer = Customer.find_or_initialize_by(reference: reference)
    customer.assign_attributes(attributes)
    status = status_of(customer)
    customer.save!
    report.count(status)
    report_update(customer, row.locator) if status == :customers_updated
  rescue ActiveRecord::RecordInvalid => error
    report_invalid(error, row.locator)
  end

  def seen
    @seen ||= {}
  end

  def attributes_for(row)
    Customer::Import::CavegestAttributes.new(row, report, source)
                                       .to_h
                                       .merge(price_grid: price_grid_for(row))
  end

  def price_grid_for(row)
    code = N.upcased(row.value("Code categ tarif", 0))
    return nil if code.nil?

    name = N.upcased(row.value("Libellé categ tarif", 0))

    grid = price_grids[code] ||= begin
      found = PriceGrid.find_or_initialize_by(code: code)
      found.name ||= name
      status = status_of(found)
      found.save!
      report.count(status)
      found
    end

    if name && grid.name != name
      report_warning(
        :price_grid_labels_conflicting,
        row.locator,
        "grille #{code} : libellés contradictoires (#{grid.name} / #{name})"
      )
    end

    grid
  end

  def price_grids
    @price_grids ||= {}
  end

  def report_duplicate(row, reference, attributes)
    if seen[reference] == attributes.hash
      report_warning(
        :duplicates_merged,
        row.locator,
        "doublon de #{reference}, ligne identique ignorée"
      )
    else
      report_error(
        :customer_duplicate_references,
        row.locator,
        "référence #{reference} déjà vue avec un contenu différent"
      )
    end
  end
end
