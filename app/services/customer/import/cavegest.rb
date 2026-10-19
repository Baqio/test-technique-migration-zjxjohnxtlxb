class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect", "R" => "customer" }.freeze

  def call
    imported = 0  
    map = Importer::HeaderMap.new(headers)

    (2..sheet.last_row).each do |line|
      row = sheet.row(line)
      next unless record?(row, map)

      Customer.create!(
        reference:         N.text(map.value(row, "Code", 0)),
        company_name:      N.text(map.value(row, "Libellé", 0)),
        first_name:        N.text(map.value(row, "Prénom", 0)),
        last_name:         N.text(map.value(row, "Nom", 0)),
        address1:          N.text(map.value(row, "Adresse", 0)),
        city:              N.text(map.value(row, "Ville", 0)),
        country_code:      N.country_code(map.value(row, "Pays", 0)),
        zip:               N.zip(map.value(row, "Code postal", 0), N.country_code(map.value(row, "Pays", 0))),
        phone:             map.value(row, "Téléphone 1", 0).to_s,
        mobile:            map.value(row, "Téléphone 2", 0).to_s,
        email:             map.value(row, "EMail", 0).to_s,
        kind:              KINDS[N.text(map.value(row, "Code famille client", 0))],
        customer_category: N.text(map.value(row, "Libellé famille client", 0)),
        price_grid_code:   N.text(map.value(row, "Code categ tarif", 0)),
        vat_number:        N.text(map.value(row, "Numéro de TVA", 0)),
        excise_number:     N.text(map.value(row, "Numéro d Accise", 0)),

        shipping_last_name:    N.text(map.value(row, "Nom", 1)),
        shipping_first_name:   N.text(map.value(row, "Prénom", 1)),
        shipping_company_name: N.text(map.value(row, "Libellé", 1)),
        shipping_address1:     N.text(map.value(row, "Adresse", 1)),
        shipping_city:         N.text(map.value(row, "Ville", 1)),
        shipping_country_code: N.country_code(map.value(row, "Pays", 1)),
        shipping_zip:          N.zip(map.value(row, "Code postal", 1), N.country_code(map.value(row, "Pays", 1))),
        shipping_phone:        map.value(row, "Téléphone 1", 1).to_s,
      )

      imported += 1
    rescue ActiveRecord::RecordInvalid => error
      report.error(
        source: source, 
        locator: "#{sheet.default_sheet} ligne #{line}",
        message: error.record.errors.full_messages.join(", ")
      )
    end

    puts "#{imported} clients importés"
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
end
