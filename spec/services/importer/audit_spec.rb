require "spec_helper"

RSpec.describe Importer::Audit do
  let(:report) { described_class.call }

  it "counts what the base holds" do
    price(product("COT196", vat_rate: 20), grid("DEPC"), 19.31)

    expect(report.counters[:products_in_base]).to eq(1)
    expect(report.counters[:product_prices_in_base]).to eq(1)
    expect(report.counters[:price_grids_in_base]).to eq(1)
  end

  it "reports a control that found nothing" do
    price(product("COT196", vat_rate: 20), grid("DEPC"), 19.31)

    expect(report.to_s).to include("Produits sans aucun tarif : 0")
  end

  it "flags a product nobody can sell" do
    product("COT196", vat_rate: 20)

    expect(report.counters[:products_without_prices]).to eq(1)
    expect(report.errors.first.message).to eq("aucun tarif")
  end

  it "flags a product nobody can invoice" do
    price(product("COT196"), grid("DEPC"), 19.31)

    expect(report.counters[:products_without_vat_rate]).to eq(1)
  end

  it "flags a price at zero" do
    price(product("COT196", vat_rate: 20), grid("DEPC"), 0)

    expect(report.counters[:product_prices_not_positive]).to eq(1)
  end

  it "flags a customer without a price grid" do
    customer("T00001")
    customer("T00002", kind: "supplier")

    expect(report.counters[:customers_without_price_grid]).to eq(1)
  end

  it "flags a grid that customers use but that has no price" do
    customer("T00001", price_grid: grid("GDCPT"))

    expect(report.counters[:price_grids_without_prices]).to eq(1)
    expect(report.errors.first.locator).to eq("grille GDCPT")
  end

  it "flags a grid that is priced but that nobody uses" do
    price(product("COT196", vat_rate: 20), grid("SALON"), 19.31)

    expect(report.counters[:price_grids_without_customers]).to eq(1)
  end

  it "says nothing about a grid that has neither prices nor customers" do
    grid("GDCPT")

    expect(report.counters[:price_grids_without_prices]).to eq(0)
    expect(report.counters[:price_grids_without_customers]).to eq(0)
  end

  it "counts a grid once whatever the number of prices it carries" do
    salon = grid("SALON")
    price(product("COT196", vat_rate: 20), salon, 19.31)
    price(product("LANM3", vat_rate: 20), salon, 13.32)

    expect(report.counters[:price_grids_without_customers]).to eq(1)
    expect(report.warnings.size).to eq(1)
  end

  it "flags a grid that does not cover the whole catalogue" do
    part = grid("PART")
    depc = grid("DEPC")
    covered = product("COT196", vat_rate: 20)
    uncovered = product("LANM3", vat_rate: 20)

    price(covered, part, 19.31)
    price(covered, depc, 19.31)
    price(uncovered, depc, 13.32)
    customer("T00001", price_grid: part)
    customer("T00002", price_grid: depc)

    expect(report.counters[:price_grids_incomplete]).to eq(1)
    expect(report.warnings.first.locator).to eq("grille PART")
  end

  it "flags two references for the same wine and the same container" do
    Product.create!(reference: "LES194", name: "Les Argiles 2019", volume_ml: 750, vat_rate: 20)
    Product.create!(reference: "LES195", name: "Les Argiles 2019", volume_ml: 750, vat_rate: 20)

    expect(report.counters[:products_possibly_duplicated]).to eq(1)
    expect(report.warnings.first.message).to eq("même désignation et même contenance")
  end

  it "does not confuse two containers of the same wine" do
    Product.create!(reference: "LES194", name: "Les Argiles 2019", volume_ml: 750, vat_rate: 20)
    Product.create!(reference: "LES195", name: "Les Argiles 2019", volume_ml: 3000, vat_rate: 20)

    expect(report.counters[:products_possibly_duplicated]).to eq(0)
  end

  it "counts the products left incomplete" do
    product("COT196", vat_rate: 20)
    product("LANM3", vat_rate: 20, volume_ml: 750, product_color: ProductColor.create!(name: "Rouge"))

    expect(report.counters[:products_without_volume]).to eq(1)
    expect(report.counters[:products_without_color]).to eq(1)
  end

it "counts the customers whose country is missing" do
    customer("T00001", country_code: "FR")
    customer("T00002")
    customer("T00003", vat_number: "FR69995954011")

    expect(report.counters[:customers_without_country]).to eq(2)
    expect(report.warnings.last.message)
      .to eq("pays retrouvable depuis le numéro de TVA pour 1 d'entre eux")
  end

  it "flags a VAT number used by two customers" do
    customer("T00001", vat_number: "FR40123456782")
    customer("T00002", vat_number: "FR40123456782")
    customer("T00003", vat_number: "FR69995954011")

    expect(report.counters[:vat_numbers_shared]).to eq(1)
    expect(report.warnings.last.locator).to eq("clients T00001, T00002")
    expect(report.warnings.last.message).to eq("même numéro de TVA FR40123456782")
  end

  it "flags two references for the same shop at the same address" do
    customer("T02200", company_name: "LE VERRE GALANT", last_name: "BOYER",
             zip: "31000", address1: "27 place du Marché")
    customer("T03415", company_name: "LE VERRE GALANT", last_name: "MARTIN",
             zip: "31000", address1: "27 place du Marché")

    expect(report.counters[:firms_possibly_duplicated]).to eq(1)
    expect(report.warnings.last.locator).to include("T02200", "T03415")
    expect(report.warnings.last.message).to eq("même enseigne à la même adresse")
  end

  it "does not confuse two shops of the same name in the same town" do
    customer("T02200", company_name: "LE VERRE GALANT", zip: "69002", address1: "1 avenue de la Gare")
    customer("T03415", company_name: "LE VERRE GALANT", zip: "69002", address1: "109 avenue de la Gare")

    expect(report.counters[:firms_possibly_duplicated]).to eq(0)
  end

  it "flags two references for the same person at the same address" do
    customer("T00117", last_name: "GARNIER", first_name: "Nadia", zip: "34000", address1: "114 grand rue")
    customer("T00305", last_name: "GARNIER", first_name: "Nadia", zip: "34000", address1: "114 grand rue")

    expect(report.counters[:people_possibly_duplicated]).to eq(1)
    expect(report.warnings.last.locator).to include("T00117", "T00305")
    expect(report.warnings.last.message).to eq("même personne à la même adresse")
  end

  it "does not take two people living together for a duplicate" do
    customer("T00117", last_name: "GARNIER", first_name: "Nadia", zip: "34000", address1: "114 grand rue")
    customer("T00305", last_name: "GARNIER", first_name: "Marc", zip: "34000", address1: "114 grand rue")

    expect(report.counters[:people_possibly_duplicated]).to eq(0)
    expect(report.to_s).to include("Particuliers de même nom à la même adresse : 0")
  end

  it "flags a creation date that cannot be one" do
    customer("T00001", creation_date: Date.new(2013, 7, 22))
    customer("T00002", creation_date: Date.new(13, 7, 22))
    customer("T00003", creation_date: Date.current + 1)

    expect(report.counters[:customers_creation_date_impossible]).to eq(2)
    expect(report.errors.map(&:locator)).to eq(["client T00002", "client T00003"])
    expect(report.errors.first.message).to eq("date de création impossible : 22/07/0013")
  end

  def grid(code)
    PriceGrid.create!(code: code)
  end

  def product(reference, **attributes)
    Product.create!(reference: reference, name: reference, **attributes)
  end

  def price(product, grid, amount)
    ProductPrice.create!(product: product, price_grid: grid, amount_ht: amount)
  end

  def customer(reference, **attributes)
    Customer.create!(reference: reference, last_name: reference, **attributes)
  end
end
