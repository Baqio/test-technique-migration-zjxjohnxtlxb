class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect", "R" => "customer" }.freeze
  SHARED_HEADERS = ["Nom", "Prénom", "Libellé", "Adresse", "Code postal", "Ville", "Pays", "Téléphone 1"].freeze

  def call
    map = Importer::HeaderMap.new(headers)
    seen = {}

    (2..sheet.last_row).each do |line|
      row = sheet.row(line)
      next unless record?(row, map)

      locator    = "#{sheet.default_sheet} ligne #{line}"
      reference  = N.text(map.value(row, "Code", 0))
      attributes = attributes_for(row, map, locator)

      next report_duplicate(seen, reference, attributes, locator) if seen.key?(reference)

      seen[reference] = attributes.hash

      customer = Customer.find_or_initialize_by(reference: reference)
      customer.assign_attributes(attributes)
      status = status_of(customer)
      customer.save!
      report.count(status)
      report_update(customer, locator) if status == :customers_updated

    rescue ActiveRecord::RecordInvalid => error
      report.error(
        source: source,
        locator: locator,
        message: error.record.errors.full_messages.join(", ")
      )
    end

    report
  end

  private

  def workbook
    @workbook ||= Roo::Excelx.new(path)
  end

  def sheet(index = 0)
    workbook.sheet(index)
  end

  def headers(index = 1)
    sheet.row(index)
  end

  def record?(row, map)
    code = N.text(map.value(row, "Code", 0))
    !code.nil? && !code.upcase.start_with?("TOTAL")
  end

  def attributes_for(row, map, locator)
    {
      company_name: N.upcased(map.value(row, "Libellé", 0)),
      first_name: N.capitalized(map.value(row, "Prénom", 0)),
      last_name: N.upcased(map.value(row, "Nom", 0)),
      address1: N.text(map.value(row, "Adresse", 0)),
      city: N.text(map.value(row, "Ville", 0)),
      country_code: N.country_code(map.value(row, "Pays", 0)),
      zip: N.zip(map.value(row, "Code postal", 0), N.country_code(map.value(row, "Pays", 0))),
      phone: map.value(row, "Téléphone 1", 0).to_s,
      mobile: map.value(row, "Téléphone 2", 0).to_s,
      email: map.value(row, "EMail", 0).to_s,
      kind: KINDS[N.text(map.value(row, "Code famille client", 0))],
      customer_category: N.text(map.value(row, "Libellé famille client", 0)),
      price_grid_code: N.text(map.value(row, "Code categ tarif", 0)),
      vat_number: N.text(map.value(row, "Numéro de TVA", 0)),
      excise_number: N.text(map.value(row, "Numéro d Accise", 0)),
      creation_date: creation_date(row, map, locator),
      active: N.text(map.value(row, "Inutilisable", 0)) != "1",
      use_billing_address: billing_address_used?(row, map),

      shipping_last_name: N.upcased(map.value(row, "Nom", 1)),
      shipping_first_name: N.capitalized(map.value(row, "Prénom", 1)),
      shipping_company_name: N.upcased(map.value(row, "Libellé", 1)),
      shipping_address1: N.text(map.value(row, "Adresse", 1)),
      shipping_city: N.text(map.value(row, "Ville", 1)),
      shipping_country_code: N.country_code(map.value(row, "Pays", 1)),
      shipping_zip: N.zip(map.value(row, "Code postal", 1), N.country_code(map.value(row, "Pays", 1))),
      shipping_phone: map.value(row, "Téléphone 1", 1).to_s
    }
  end

  def status_of(customer)
    return :customers_created if customer.new_record?
    return :customers_updated if customer.changed?

    :customers_unchanged
  end

  def report_duplicate(seen, reference, attributes, locator)
    if seen[reference] == attributes.hash
      report.count(:duplicates_merged)
      report.warn(
        source: source,
        locator: locator,
        message: "doublon de #{reference}, ligne identique ignorée"
      )
    else
      report.error(
        source: source,
        locator: locator,
        message: "référence #{reference} déjà vue avec un contenu différent"
      )
    end
  end

  def report_update(customer, locator)
    report.warn(
      source: source, locator: locator,
      message: "#{customer.reference} mis à jour",
      changes: customer.previous_changes.except("updated_at")
    )
  end

  def creation_date(row, map, locator)
    value = map.value(row, "Date de création", 0)
    N.date(value)
  rescue Date::Error
    report.warn(
      source: source,
      locator: locator,
      message: "date de création illisible : #{value.inspect}"
    )

    nil
  end

  def billing_address_used?(row, map)
    shipping = SHARED_HEADERS.map { |header| N.text(map.value(row, header, 1)) }
    return true if shipping.compact.empty?

    shipping == SHARED_HEADERS.map { |header| N.text(map.value(row, header, 0)) }
  end
end
