class ProductPrice::Import::CavegestAttributes
  include Importer::Reporting

  N = Importer::Normalization

  # « Bouteille - 75.0 » : le nombre après le tiret est une contenance en centilitres.
  CENTILITRES = /-\s*(\d+(?:[.,]\d+)?)\s*\z/

  def initialize(row, report, source)
    @row    = row
    @report = report
    @source = source
  end

  def to_h
    {
      name: N.text(row.value("Désignation")),
      volume_ml: volume_ml_of,
      vat_rate: vat_rate_of,
      stock: stock_of
    }
  end

  private

  attr_reader :row, :report, :source

  def volume_ml_of
    raw = N.text(row.value("Contenant"))

    if raw.nil?
      report_warning(
        :product_volumes_missing,
        row.locator,
        "contenant absent"
      )

      return nil
    end

    centilitres, parsing = N.decimal(raw[CENTILITRES, 1])
    volume = (centilitres * 10).to_i if parsing == :ok
    return volume if volume&.positive?

    report_warning(
      :product_volumes_unreadable,
      row.locator,
      "contenant illisible, volume non repris : #{raw}"
    )

    nil
  end

  def vat_rate_of
    rate, parsing = N.decimal(row.value("TVA"))
    return rate if parsing == :ok

    report_warning(
      :product_vat_rates_missing,
      row.locator,
      "taux de TVA illisible, non repris : #{N.text(row.value("TVA")).inspect}"
    )

    nil
  end

  def stock_of
    quantity, parsing = N.decimal(row.value("Stock"))
    return quantity.to_i if parsing == :ok

    report_warning(
      :product_stocks_missing,
      row.locator,
      "stock illisible, non repris : #{N.text(row.value("Stock")).inspect}"
    )

    nil
  end
end
