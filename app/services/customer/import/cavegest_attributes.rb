class Customer::Import::CavegestAttributes
  include Importer::Reporting

  N = Importer::Normalization

  # « R » (revendeur) n'existe pas comme kind dans Baqio : la distinction est
  # commerciale, pas fonctionnelle. Elle reste portée par customer_category.
  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect", "R" => "customer" }.freeze
  SHARED_HEADERS = ["Nom", "Prénom", "Libellé", "Adresse", "Code postal", "Ville", "Pays", "Téléphone 1"].freeze

  def initialize(row, report, source)
    @row    = row
    @report = report
    @source = source
  end

  def to_h
    country          = country_of(0)
    shipping_country = country_of(1)

    {
      company_name: N.upcased(row.value("Libellé", 0)),
      first_name: N.capitalized(row.value("Prénom", 0)),
      last_name: N.upcased(row.value("Nom", 0)),
      address1: N.text(row.value("Adresse", 0)),
      city: N.text(row.value("Ville", 0)),
      country_code: country,
      zip: zip_of(0, country),
      phone: phone_number_of(0, country, "Téléphone 1"),
      mobile: phone_number_of(0, country, "Téléphone 2"),
      email: email_of,
      kind: kind_of,
      customer_category: N.upcased(row.value("Libellé famille client", 0)),
      vat_number: vat_number_of(country),
      excise_number: excise_number_of,
      creation_date: creation_date_of,
      active: N.text(row.value("Inutilisable", 0)) != "1",
      use_billing_address: billing_address_used?,

      shipping_last_name: N.upcased(row.value("Nom", 1)),
      shipping_first_name: N.capitalized(row.value("Prénom", 1)),
      shipping_company_name: N.upcased(row.value("Libellé", 1)),
      shipping_address1: N.text(row.value("Adresse", 1)),
      shipping_city: N.text(row.value("Ville", 1)),
      shipping_country_code: shipping_country,
      shipping_zip: zip_of(1, shipping_country),
      shipping_phone: phone_number_of(1, shipping_country, "Téléphone 1")
    }
  end

  private

  attr_reader :row, :report, :source

  def labelled(text, rank)
    rank.zero? ? text : "#{text} (livraison)"
  end

  def country_of(rank)
    value = row.value("Pays", rank)
    label = labelled("pays", rank)
    code  = N.country_code(value)
    return code if code || N.text(value).nil?

    report_warning(
      :countries_unknown,
      row.locator,
      "#{label} non reconnu, non repris : #{N.text(value)}"
    )

    nil
  end

  def zip_of(rank, country)
    value = row.value("Code postal", rank)
    label = labelled("code postal", rank)
    code, status = N.zip(value, country)

    case status
    when :padded
      report_warning(
        country ? :zips_completed : :zips_completed_assumed_country,
        row.locator,
        "#{label} complété (#{country || "#{N::DEFAULT_COUNTRY} par défaut"}) : #{N.text(value)} -> #{code}"
      )
    when :kept
      report_warning(
        :zips_kept,
        row.locator,
        "#{label} non conforme au format #{country || N::DEFAULT_COUNTRY}, valeur conservée : #{code}"
      )
    when :unexpected
      report_warning(
        :zips_unexpected,
        row.locator,
        "#{label} : #{country} n'utilise pas de code postal, valeur conservée : #{code}"
      )
    when :placeholder
      report_warning(
        :zips_placeholder,
        row.locator,
        "#{label} noté « #{N.text(value)} », non repris"
      )
    end

    code
  end

  def phone_number_of(rank, country, header)
    value = row.value(header, rank)
    label = labelled(header, rank)
    number, status = N.phone(value, country)

    case status
    when :normalized
      report.count(:phones_normalized)
    when :kept
      report_warning(
        :phones_kept,
        row.locator,
        "#{label} non reconnu, conservé reformaté : #{N.text(value)} -> #{number}"
      )
    when :rejected
      report_warning(
        :phones_rejected,
        row.locator,
        "#{label} illisible, non repris : #{N.text(value)}"
      )
    when :placeholder
      report_warning(
        :phones_placeholder,
        row.locator,
        "#{label} noté « #{N.text(value)} », non repris"
      )
    end

    number
  end

  def email_of
    value = row.value("EMail", 0)
    address, status = N.email(value)

    case status
    when :rejected
      report_warning(
        :emails_rejected,
        row.locator,
        "adresse e-mail invalide, non reprise : #{N.text(value)}"
      )
    when :placeholder
      report_warning(
        :emails_placeholder,
        row.locator,
        "adresse e-mail notée « #{N.text(value)} », non reprise"
      )
    end

    address
  end

  def vat_number_of(country)
    value = row.value("Numéro de TVA", 0)
    number, status = N.vat_number(value, country)

    case status
    when :mismatch
      report_warning(
        :vat_numbers_country_mismatch,
        row.locator,
        "numéro de TVA #{number} incohérent avec le pays #{country}"
      )
    when :placeholder
      report_warning(
        :vat_numbers_placeholder,
        row.locator,
        "numéro de TVA noté « #{N.text(value)} », non repris"
      )
    when :invalid
      report_warning(
        :vat_numbers_invalid,
        row.locator,
        "numéro de TVA au format invalide, conservé : #{number}"
      )
    end

    number
  end

  def excise_number_of
    value = row.value("Numéro d Accise", 0)
    number, status = N.excise_number(value)

    case status
    when :padded
      report_warning(
        :excise_numbers_completed,
        row.locator,
        "numéro d'accise complété au format SEED : #{N.text(value)} -> #{number}"
      )
    when :kept
      report_warning(
        :excise_numbers_kept,
        row.locator,
        "numéro d'accise au format inattendu, conservé : #{number}"
      )
    when :placeholder
      report_warning(
        :excise_numbers_placeholder,
        row.locator,
        "numéro d'accise noté « #{N.text(value)} », non repris"
      )
    end

    number
  end

  def creation_date_of
    value = row.value("Date de création", 0)
    N.date(value)
  rescue Date::Error
    report_warning(
      :creation_dates_unreadable,
      row.locator,
      "date de création illisible : #{value.inspect}"
    )

    nil
  end

  def kind_of
    code = N.text(row.value("Code famille client", 0))&.upcase
    kind = KINDS[code]

    if kind.nil?
      report_warning(
        :kinds_unknown,
        row.locator,
        "code famille client inconnu : #{code.inspect}"
      )

      return nil
    end

    report.count(:kinds_resellers_as_customers) if code == "R"

    kind
  end

  def billing_address_used?
    shipping = SHARED_HEADERS.map { |header| N.text(row.value(header, 1)) }
    return true if shipping.compact.empty?

    shipping == SHARED_HEADERS.map { |header| N.text(row.value(header, 0)) }
  end
end
