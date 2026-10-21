class Importer::Audit
  SOURCE = "base".freeze

  TABLES = [
    Customer,
    Product,
    ProductPrice,
    PriceGrid,
    ProductClassification,
    ProductColor
  ].freeze

  attr_reader :report

  def self.call = new.call

  def initialize(
    report: MigrationReport.new(title: "Contrôles de cohérence après reprise")
  )
    @report = report
  end

  def call
    check_volumetry

    check_products_without_prices
    check_products_without_vat_rate
    check_prices_not_positive
    check_customers_without_price_grid
    check_grids_without_prices

    check_grids_without_customers
    check_grids_missing_products
    check_duplicate_products
    check_incomplete_products

    report
  end

  def to_s
    call.to_s
  end

  private

  def check_volumetry
    TABLES.each { |model| report.count(:"#{model.table_name}_in_base", model.count) }
  end

  def check_products_without_prices
    products = Product.where.missing(:product_prices)
    report.count(:products_without_prices, products.count)

    products.find_each do |product|
      report.error(
        source: SOURCE,
        locator: "produit #{product.reference}",
        message: "aucun tarif"
      )
    end
  end

  def check_products_without_vat_rate
    products = Product.where(vat_rate: nil)
    report.count(:products_without_vat_rate, products.count)

    products.find_each do |product|
      report.error(
        source: SOURCE,
        locator: "produit #{product.reference}",
        message: "aucun taux de TVA"
      )
    end
  end

  def check_prices_not_positive
    prices = ProductPrice.where(amount_ht: ..0)
    report.count(:product_prices_not_positive, prices.count)

    prices.includes(:product, :price_grid).find_each do |price|
      report.error(
        source: SOURCE,
        locator: "tarif #{price.price_grid.code} de #{price.product.reference}",
        message: "montant HT à #{price.amount_ht}"
      )
    end
  end

  def check_customers_without_price_grid
    customers = Customer.where(kind: "customer", price_grid_id: nil)
    report.count(:customers_without_price_grid, customers.count)
  end

  def check_grids_without_prices
    grids = PriceGrid.where.missing(:product_prices).where.associated(:customers).distinct
    report.count(:price_grids_without_prices, grids.count)

    customers = Customer.group(:price_grid_id).count

    grids.find_each do |grid|
      report.error(
        source: SOURCE,
        locator: "grille #{grid.code}",
        message: "#{customers[grid.id]} clients sur une grille sans aucun tarif"
      )
    end
  end

  def check_grids_without_customers
    grids = PriceGrid.where.associated(:product_prices).where.missing(:customers).distinct
    report.count(:price_grids_without_customers, grids.count)

    priced = ProductPrice.group(:price_grid_id).count

    grids.find_each do |grid|
      report.warn(
        source: SOURCE,
        locator: "grille #{grid.code}",
        message: "#{priced[grid.id]} tarifs sur une grille qu'aucun client n'utilise"
      )
    end
  end

  def check_grids_missing_products
    catalogue  = Product.count
    priced     = ProductPrice.group(:price_grid_id).count
    incomplete = priced.reject { |_, covered| covered == catalogue }

    report.count(:price_grids_incomplete, incomplete.size)

    PriceGrid.where(id: incomplete.keys).find_each do |grid|
      report.warn(
        source: SOURCE,
        locator: "grille #{grid.code}",
        message: "#{catalogue - priced[grid.id]} produits sans tarif dans cette grille"
      )
    end
  end

  def check_duplicate_products
    duplicates = Product.group(:name, :volume_ml).having("count(*) > 1").count.keys
    report.count(:products_possibly_duplicated, duplicates.size)
    return if duplicates.empty?

    references = Product.where(name: duplicates.map(&:first))
                        .pluck(:name, :volume_ml, :reference)
                        .group_by { |name, volume_ml, _| [name, volume_ml] }

    duplicates.each do |key|
      report.warn(
        source: SOURCE,
        locator: "produits #{references[key].map(&:last).join(', ')}",
        message: "même désignation et même contenance"
      )
    end
  end

  def check_incomplete_products
    report.count(:products_without_volume, Product.where(volume_ml: nil).count)
    report.count(:products_without_color, Product.where(product_color_id: nil).count)
  end
end
