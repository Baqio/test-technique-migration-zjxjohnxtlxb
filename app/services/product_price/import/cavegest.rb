class ProductPrice::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  FALLBACK_ENCODING = "Windows-1252".freeze
  COLUMN_SEP = ";".freeze
  CSV_OPTIONS = {
    headers: true,
    col_sep: COLUMN_SEP,
    liberal_parsing: true
  }.freeze

  # « --- AOP ROUGES --- » : section du catalogue, pas un produit.
  SECTION = /\A-+\s*(.+?)\s*-+\z/

  GRID_CODES = %w[DEPC CHR EXPO PART SALON].freeze
  PRODUCT_COLUMNS = %w[Ref Désignation Contenant Couleur TVA Stock].freeze

  # La grille EXPO est saisie en TTC dans CaveGest, on stocke du HT.
  TAX_INCLUDED_GRIDS = %w[EXPO].freeze

  def call
    declare_price_grids

    each_row do |row|
      reference = N.text(row.value("Ref"))
      next if reference.nil?

      case line_kind(reference)
      when :section then @classification = classification_for(reference[SECTION, 1])
      when :total   then collect_declared_total(reference, row)
      when :product then import_product(row, reference)
      end
    end

    reconcile_declared_totals

    report
  end

  private

  def declare_price_grids
    GRID_CODES.each do |code|
      grid = PriceGrid.find_or_initialize_by(code: code)
      grid.tax_included = TAX_INCLUDED_GRIDS.include?(code)
      status = status_of(grid)
      grid.save!
      report.count(status)
      price_grids[code] = grid
    end
  end

  def price_grids
    @price_grids ||= {}
  end

  def content
    @content ||= begin
      raw = File.read(path, encoding: "UTF-8")
      raw.valid_encoding? ? raw : File.read(path, encoding: FALLBACK_ENCODING).encode("UTF-8")
    end
  end

  def each_row
    offset = content.lines.index { |l| l.start_with?("Ref#{COLUMN_SEP}") }

    if offset.nil?
      report_error(
        :headers_not_found,
        "en-tête",
        "ligne d'en-tête introuvable"
      )

      return
    end

    csv = CSV.new(content.lines.drop(offset).join, **CSV_OPTIONS)
    check_grid_columns(csv.first&.headers || [])
    csv.rewind
    csv.each { |cells| yield Importer::Row.new(cells, "ligne #{csv.lineno + offset}") }
  end

  def check_grid_columns(headers)
    columns = headers.compact

    (columns - PRODUCT_COLUMNS - GRID_CODES).each do |column|
      report_warning(
        :price_grid_columns_unknown,
        "en-tête",
        "colonne inconnue, non reprise : #{column}"
      )
    end

    (GRID_CODES - columns).each do |code|
      report_warning(
        :price_grid_columns_missing,
        "en-tête",
        "grille #{code} absente de l'export"
      )
    end
  end

  def line_kind(reference)
    return :section if reference.match?(SECTION)
    return :total if reference.upcase.start_with?("TOTAL", "SOUS-TOTAL")

    :product
  end

  def classification_for(name)
    section = N.upcased(name)

    classifications[section] ||= begin
      classification = ProductClassification.find_or_initialize_by(name: section)

      if classification.new_record?
        classification.position = classifications.size + 1
        classification.save!
        report.count(:product_classifications_created)
      end

      classification
    end
  end

  def classifications
    @classifications ||= {}
  end

  def collect_declared_total(reference, row)
    section = N.upcased(reference.sub(/\ASOUS-TOTAL\s*/i, ""))
    declared, = N.decimal(row.value("Stock"))

    declared_totals[section] = declared.to_i
  end

  def declared_totals
    @declared_totals ||= {}
  end

  def import_product(row, reference)
    attributes = attributes_for(row)
    fingerprint = [attributes, GRID_CODES.map { |code| row.value(code) }].hash

    return report_duplicate(row, reference, fingerprint) if seen.key?(reference)

    seen[reference] = fingerprint

    if @classification.nil?
      report_warning(
        :products_without_classification,
        row.locator,
        "produit hors section : #{reference}"
      )
    end

    product = Product.find_or_initialize_by(reference: reference)
    product.assign_attributes(attributes)
    status = status_of(product)
    product.save!
    report.count(status)
    report_update(product, row.locator) if status == :products_updated
    retained_counts[@classification&.name] += 1

    import_prices(product, row)
  rescue ActiveRecord::RecordInvalid => error
    report_invalid(error, row.locator)
  end

  def seen
    @seen ||= {}
  end

  def report_duplicate(row, reference, fingerprint)
    if seen[reference] == fingerprint
      report_warning(
        :duplicates_merged,
        row.locator,
        "doublon de #{reference}, ligne identique ignorée"
      )
    else
      report_error(
        :product_duplicate_references,
        row.locator,
        "référence #{reference} déjà utilisée par un autre produit"
      )
    end
  end

  def retained_counts
    @retained_counts ||= Hash.new(0)
  end

  def attributes_for(row)
    attributes = ProductPrice::Import::CavegestAttributes.new(row, report, source).to_h

    attributes.merge(product_color: color_for(row), product_classification: @classification)
  end

  def color_for(row)
    name = N.capitalized(row.value("Couleur"))
    return nil if name.nil?

    colors[name] ||= begin
      color = ProductColor.find_or_initialize_by(name: name)

      if color.new_record?
        color.save!
        report.count(:product_colors_created)
      end

      color
    end
  end

  def colors
    @colors ||= {}
  end

  def import_prices(product, row)
    price_grids.each do |code, grid|
      amount, parsing = N.decimal(row.value(code))

      next if parsing == :blank
      next report_invalid_price(row, code) if parsing == :invalid

      if grid.tax_included
        next report_missing_vat_rate(row, code) if product.vat_rate.nil?

        amount = tax_excluded(amount, product.vat_rate)
        report.count(:product_prices_converted)
      end

      price = ProductPrice.find_or_initialize_by(product: product, price_grid: grid)
      price.amount_ht = amount.round(2)
      status = status_of(price)
      price.save!
      report.count(status)
    end
  end

  def tax_excluded(amount, vat_rate)
    return amount if vat_rate.nil? || vat_rate.zero?

    amount / (1 + vat_rate / 100)
  end

  def report_invalid_price(row, grid_code)
    report_warning(
      :product_prices_invalid,
      row.locator,
      "tarif #{grid_code} illisible, non repris : #{N.text(row.value(grid_code))}"
    )
  end

  def report_missing_vat_rate(row, grid_code)
    report_warning(
      :product_prices_without_vat_rate,
      row.locator,
      "tarif #{grid_code} saisi en TTC sans taux de TVA, non repris"
    )
  end

  def reconcile_declared_totals
    declared_totals.each do |section, declared|
      kept = retained_counts[section]
      next if kept == declared

      report_warning(
        :product_sections_incomplete,
        "section #{section}",
        "#{declared} produits annoncés, #{kept} repris"
      )
    end
  end
end
