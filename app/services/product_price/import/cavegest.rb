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

  CENTILITRES = /-\s*(\d+(?:[.,]\d+)?)\s*\z/

  def call
    declare_price_grids

    each_row do |row, locator|
      reference = N.text(row["Ref"])
      next if reference.nil?

      case line_kind(reference)
      when :section then @classification = classification_for(reference[SECTION, 1])
      when :total   then collect_declared_total(reference, row)
      when :product then import_product(row, reference, locator)
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
      report.error(
        source: source,
        locator: source,
        message: "ligne d'en-tête introuvable"
      )

      return
    end

    csv = CSV.new(content.lines.drop(offset).join, **CSV_OPTIONS)
    check_grid_columns(csv.first&.headers || [])
    csv.rewind
    csv.each { |row| yield row, "#{source} ligne #{csv.lineno + offset}" }
  end

  def check_grid_columns(headers)
    columns = headers.compact

    (columns - PRODUCT_COLUMNS - GRID_CODES).each do |column|
      report.count(:price_grid_columns_unknown)
      report.warn(
        source: source,
        locator: "#{source} en-tête",
        message: "colonne inconnue, non reprise : #{column}"
      )
    end

    (GRID_CODES - columns).each do |code|
      report.count(:price_grid_columns_missing)
      report.warn(
        source: source,
        locator: "#{source} en-tête",
        message: "grille #{code} absente de l'export"
      )
    end
  end

  def line_kind(reference)
    return :section if reference.match?(SECTION)
    return :total if reference.upcase.start_with?("TOTAL", "SOUS-TOTAL")

    :product
  end

  def classification_for(name)
    classification = ProductClassification.find_or_initialize_by(name: N.upcased(name))

    if classification.new_record?
      @sections = (@sections || 0) + 1
      classification.position = @sections
      classification.save!
      report.count(:product_classifications_created)
    end

    classification
  end

  def collect_declared_total(reference, row)
    section = N.upcased(reference.sub(/\ASOUS-TOTAL\s*/i, ""))
    declared, = N.decimal(row["Stock"])

    declared_totals[section] = declared.to_i
  end

  def declared_totals
    @declared_totals ||= {}
  end

  def import_product(row, reference, locator)
    attributes = attributes_for(row, locator)
    fingerprint = [attributes, GRID_CODES.map { |code| row[code] }].hash

    return report_duplicate(reference, fingerprint, locator) if seen.key?(reference)

    seen[reference] = fingerprint

    if @classification.nil?
      report.count(:products_without_classification)
      report.warn(
        source: source,
        locator: locator,
        message: "produit hors section : #{reference}"
      )
    end

    product = Product.find_or_initialize_by(reference: reference)
    product.assign_attributes(attributes)
    status = status_of(product)
    product.save!
    report.count(status)
    report_update(product, locator) if status == :products_updated
    retained_counts[@classification&.name] += 1

    import_prices(product, row, locator)
  rescue ActiveRecord::RecordInvalid => error
    report_invalid(error, locator)
  end

  def seen
    @seen ||= {}
  end

  def report_duplicate(reference, fingerprint, locator)
    if seen[reference] == fingerprint
      report.count(:duplicates_merged)
      report.warn(
        source: source,
        locator: locator,
        message: "doublon de #{reference}, ligne identique ignorée"
      )
    else
      report.count(:product_duplicate_references)
      report.error(
        source: source,
        locator: locator,
        message: "référence #{reference} déjà utilisée par un autre produit"
      )
    end
  end

  def retained_counts
    @retained_counts ||= Hash.new(0)
  end

  def attributes_for(row, locator)
    {
      name: N.text(row["Désignation"]),
      product_color: color_for(row),
      volume_ml: volume_ml_of(row, locator),
      vat_rate: vat_rate_of(row, locator),
      stock: stock_of(row, locator),
      product_classification: @classification
    }
  end

  def volume_ml_of(row, locator)
    raw = N.text(row["Contenant"])

    if raw.nil?
      report.count(:product_volumes_missing)
      report.warn(
        source: source,
        locator: locator,
        message: "contenant absent"
      )

      return nil
    end

    centilitres, parsing = N.decimal(raw[CENTILITRES, 1])
    volume = (centilitres * 10).to_i if parsing == :ok
    return volume if volume&.positive?

    report.count(:product_volumes_unreadable)
    report.warn(
      source: source,
      locator: locator,
      message: "contenant illisible, volume non repris : #{raw}"
    )

    nil
  end

  def vat_rate_of(row, locator)
    rate, parsing = N.decimal(row["TVA"])
    return rate if parsing == :ok

    report.count(:product_vat_rates_missing)
    report.warn(
      source: source,
      locator: locator,
      message: "taux de TVA illisible, non repris : #{N.text(row["TVA"]).inspect}"
    )

    nil
  end

  def stock_of(row, locator)
    quantity, parsing = N.decimal(row["Stock"])
    return quantity.to_i if parsing == :ok

    report.count(:product_stocks_missing)
    report.warn(
      source: source,
      locator: locator,
      message: "stock illisible, non repris : #{N.text(row["Stock"]).inspect}"
    )

    nil
  end

  def color_for(row)
    name = N.capitalized(row["Couleur"])
    return nil if name.nil?

    color = ProductColor.find_or_initialize_by(name: name)

    if color.new_record?
      color.save!
      report.count(:product_colors_created)
    end

    color
  end

  def import_prices(product, row, locator)
    price_grids.each do |code, grid|
      amount, parsing = N.decimal(row[code])

      next if parsing == :blank
      next report_invalid_price(code, row[code], locator) if parsing == :invalid

      if grid.tax_included
        next report_missing_vat_rate(code, locator) if product.vat_rate.nil?

        amount = tax_excluded(amount, product.vat_rate)
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

  def report_invalid_price(grid_code, value, locator)
    report.count(:product_prices_invalid)
    report.warn(
      source: source,
      locator: locator,
      message: "tarif #{grid_code} illisible, non repris : #{N.text(value)}"
    )
  end

  def report_missing_vat_rate(grid_code, locator)
    report.count(:product_prices_without_vat_rate)
    report.warn(
      source: source,
      locator: locator,
      message: "tarif #{grid_code} saisi en TTC sans taux de TVA, non repris"
    )
  end

  def reconcile_declared_totals
    declared_totals.each do |section, declared|
      kept = retained_counts[section]
      next if kept == declared

      report.count(:product_sections_incomplete)
      report.warn(
        source: source,
        locator: "#{source} section #{section}",
        message: "#{declared} produits annoncés, #{kept} repris"
      )
    end
  end
end
