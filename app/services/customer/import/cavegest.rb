class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  # « R » (revendeur) n'existe pas comme kind dans Baqio : la distinction est
  # commerciale, pas fonctionnelle. Elle reste portée par customer_category.
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

  def labelled(text, rank)
    rank.zero? ? text : "#{text} (livraison)"
  end

  def attributes_for(row, map, locator)
    country          = country_of(row, map, 0, locator)
    shipping_country = country_of(row, map, 1, locator)

    {
      company_name: N.upcased(map.value(row, "Libellé", 0)),
      first_name: N.capitalized(map.value(row, "Prénom", 0)),
      last_name: N.upcased(map.value(row, "Nom", 0)),
      address1: N.text(map.value(row, "Adresse", 0)),
      city: N.text(map.value(row, "Ville", 0)),
      country_code: country,
      zip: zip_of(row, map, 0, country, locator),
      phone: phone_number_of(row, map, 0, country, locator, "Téléphone 1"),
      mobile: phone_number_of(row, map, 0, country, locator, "Téléphone 2"),
      email: email_of(row, map, locator),
      kind: kind_of(row, map, locator),
      customer_category: N.upcased(map.value(row, "Libellé famille client", 0)),
      price_grid_code: N.upcased(map.value(row, "Code categ tarif", 0)),
      vat_number: vat_number_of(row, map, country, locator),
      excise_number: excise_number_of(row, map, locator),
      creation_date: creation_date(row, map, locator),
      active: N.text(map.value(row, "Inutilisable", 0)) != "1",
      use_billing_address: billing_address_used?(row, map),

      shipping_last_name: N.upcased(map.value(row, "Nom", 1)),
      shipping_first_name: N.capitalized(map.value(row, "Prénom", 1)),
      shipping_company_name: N.upcased(map.value(row, "Libellé", 1)),
      shipping_address1: N.text(map.value(row, "Adresse", 1)),
      shipping_city: N.text(map.value(row, "Ville", 1)),
      shipping_country_code: shipping_country,
      shipping_zip: zip_of(row, map, 1, shipping_country, locator),
      shipping_phone: phone_number_of(row, map, 1, shipping_country, locator, "Téléphone 1")
    }
  end

  def country_of(row, map, rank, locator)
    value = map.value(row, "Pays", rank)
    label = labelled("pays", rank)
    code  = N.country_code(value)
    return code if code || N.text(value).nil?

    report.count(:countries_unknown)
    report.warn(
      source: source,
      locator: locator,
      message: "#{label} non reconnu, non repris : #{N.text(value)}"
    )

    nil
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

  def zip_of(row, map, rank, country, locator)
    value = map.value(row, "Code postal", rank)
    label = labelled("code postal", rank)
    code, status = N.zip(value, country)

    case status
    when :padded
      report.count(country ? :zips_completed : :zips_completed_assumed_country)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} complété (#{country || "#{N::DEFAULT_COUNTRY} par défaut"}) : #{N.text(value)} -> #{code}"
      )
    when :kept
      report.count(:zips_kept)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} non conforme au format #{country || N::DEFAULT_COUNTRY}, valeur conservée : #{code}"
      )
    when :unexpected
      report.count(:zips_unexpected)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} : #{country} n'utilise pas de code postal, valeur conservée : #{code}"
      )
    when :placeholder
      report.count(:zips_placeholder)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} noté « #{N.text(value)} », non repris"
      )
    end

    code
  end

  def phone_number_of(row, map, rank, country, locator, header)
    value = map.value(row, header, rank)
    label = labelled(header, rank)
    number, status = N.phone(value, country)

    case status
    when :normalized
      report.count(:phones_normalized)
    when :kept
      report.count(:phones_kept)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} non reconnu, conservé reformaté : #{N.text(value)} -> #{number}"
      )
    when :rejected
      report.count(:phones_rejected)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} illisible, non repris : #{N.text(value)}"
      )
    when :placeholder
      report.count(:phones_placeholder)
      report.warn(
        source: source,
        locator: locator,
        message: "#{label} noté « #{N.text(value)} », non repris"
      )
    end

    number
  end

  def email_of(row, map, locator)
    value = map.value(row, "EMail", 0)
    address, status = N.email(value)

    case status
    when :rejected
      report.count(:emails_rejected)
      report.warn(
        source: source,
        locator: locator,
        message: "adresse e-mail invalide, non reprise : #{N.text(value)}"
      )
    when :placeholder
      report.count(:emails_placeholder)
      report.warn(
        source: source,
        locator: locator,
        message: "adresse e-mail notée « #{N.text(value)} », non reprise"
      )
    end

    address
  end

  def vat_number_of(row, map, country, locator)
    value = map.value(row, "Numéro de TVA", 0)
    number, status = N.vat_number(value, country)

    case status
    when :mismatch
      report.count(:vat_numbers_country_mismatch)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro de TVA #{number} incohérent avec le pays #{country}"
      )
    when :placeholder
      report.count(:vat_numbers_placeholder)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro de TVA noté « #{N.text(value)} », non repris"
      )
    when :invalid
      report.count(:vat_numbers_invalid)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro de TVA au format invalide, conservé : #{number}"
      )
    end

    number
  end

  def excise_number_of(row, map, locator)
    value = map.value(row, "Numéro d Accise", 0)
    number, status = N.excise_number(value)

    case status
    when :padded
      report.count(:excise_numbers_completed)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro d'accise complété au format SEED : #{N.text(value)} -> #{number}"
      )
    when :kept
      report.count(:excise_numbers_kept)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro d'accise au format inattendu, conservé : #{number}"
      )
    when :placeholder
      report.count(:excise_numbers_placeholder)
      report.warn(
        source: source,
        locator: locator,
        message: "numéro d'accise noté « #{N.text(value)} », non repris"
      )
    end

    number
  end

  def kind_of(row, map, locator)
    code = N.text(map.value(row, "Code famille client", 0))&.upcase
    kind = KINDS[code]

    if kind.nil?
      report.count(:kinds_unknown)
      report.warn(
        source: source,
        locator: locator,
        message: "code famille client inconnu : #{code.inspect}"
      )

      return nil
    end

    report.count(:kinds_resellers_as_customers) if code == "R"

    kind
  end

  def billing_address_used?(row, map)
    shipping = SHARED_HEADERS.map { |header| N.text(map.value(row, header, 1)) }
    return true if shipping.compact.empty?

    shipping == SHARED_HEADERS.map { |header| N.text(map.value(row, header, 0)) }
  end
end
