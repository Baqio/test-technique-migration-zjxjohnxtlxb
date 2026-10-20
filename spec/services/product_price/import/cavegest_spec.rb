require "spec_helper"

RSpec.describe ProductPrice::Import::Cavegest do
  before(:all) do
    @report = described_class.new(data_path("export_tarifs_cavegest.csv"), report: MigrationReport.new).call
  end

  after(:all) do
    ProductPrice.delete_all
    Product.delete_all
    ProductColor.delete_all
    ProductPrice.delete_all
    Product.delete_all
    ProductColor.delete_all
    ProductClassification.delete_all
    PriceGrid.delete_all
  end

  let(:report) { @report }

  it "reads the file whatever its encoding" do
    expect(Product.find_by(reference: "SEL208").name).to eq("Sélection du Domaine 2020")
  end

  it "skips the section and subtotal rows" do
    expect(Product.where("reference LIKE '---%' OR reference LIKE 'SOUS-TOTAL%'")).to be_empty
    expect(Product.count).to eq(107)
  end

  it "keeps the first of two products sharing a reference" do
    expect(Product.find_by(reference: "HAU214").name).to eq("Haut Montcalm 2021")
    expect(report.errors.size).to eq(6)
  end

  it "declares the price grids of the export" do
    expect(PriceGrid.pluck(:code)).to match_array(%w[DEPC CHR EXPO PART SALON])
    expect(PriceGrid.find_by(code: "EXPO").tax_included).to be(true)
  end

  it "reads the French decimal separator" do
    expect(price("LANM3", "DEPC")).to eq(13.32)
  end

  it "reads a price with a currency suffix" do
    expect(price("COT196", "DEPC")).to eq(19.31)
  end

  it "converts the EXPO grid from tax-included to tax-excluded" do
    expect(price("LANM3", "EXPO")).to eq(13.32)
  end

  it "uses the product's own rate for the conversion" do
    expect(Product.find_by(reference: "TRA231").vat_rate).to eq(5.5)
    expect(price("TRA231", "EXPO")).to eq(11.66)
  end

  it "reads a VAT rate written with a percent sign" do
    expect(Product.find_by(reference: "TRA232").vat_rate).to eq(20)
  end

  it "stores no price for an empty cell" do
    expect(price("LANM3", "SALON")).to be_nil
    expect(price("CUV234", "SALON")).to eq(12.95)
  end

  it "reads the volume from the container" do
    expect(Product.find_by(reference: "LANM3").volume_ml).to eq(3000)
    expect(Product.find_by(reference: "CUV234").volume_ml).to eq(375)
  end

  it "leaves the volume empty when the container is not a capacity" do
    expect(Product.find_by(reference: "TRA195").volume_ml).to be_nil
    expect(Product.find_by(reference: "FUTNM7").volume_ml).to be_nil
  end

  it "normalizes the colour" do
    expect(Product.find_by(reference: "SEL208").product_color.name).to eq("Blanc")
    expect(Product.find_by(reference: "CUV234").product_color.name).to eq("Blanc")
    expect(ProductColor.count).to eq(3)
  end

  it "leaves the colour empty when it is not filled in" do
    expect(Product.find_by(reference: "CUV227").product_color).to be_nil
  end

  it "attaches each product to the section it is listed under" do
    expect(Product.find_by(reference: "LANM3").product_classification.name).to eq("AOP ROUGES")
    expect(ProductClassification.order(:position).pluck(:name).first).to eq("AOP ROUGES")
    expect(Product.where(product_classification_id: nil)).to be_empty
  end

  it "creates nothing on a second run" do
    second = MigrationReport.new

    expect { described_class.new(data_path("export_tarifs_cavegest.csv"), report: second).call }
      .not_to change(Product, :count)

    expect(second.counters[:products_created]).to eq(0)
    expect(second.counters[:products_unchanged]).to eq(107)
    expect(second.counters[:product_prices_unchanged]).to eq(476)
  end

  it "counts what it imported" do
    expect(report.counters[:price_grids_created]).to eq(5)
    expect(report.counters[:product_classifications_created]).to eq(6)
    expect(report.counters[:product_colors_created]).to eq(3)
    expect(report.counters[:products_created]).to eq(107)
    expect(report.counters[:product_prices_created]).to eq(476)
    expect(report.counters[:product_volumes_missing]).to eq(13)
    expect(report.counters[:product_volumes_unreadable]).to eq(2)
    expect(report.counters[:product_duplicate_references]).to eq(6)
  end

  def price(reference, code)
    ProductPrice.joins(:product, :price_grid)
                .find_by(products: { reference: reference }, price_grids: { code: code })
                &.amount_ht
  end
end
