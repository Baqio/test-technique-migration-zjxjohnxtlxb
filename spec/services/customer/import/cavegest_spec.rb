require "spec_helper"

RSpec.describe Customer::Import::Cavegest do
  before(:all) do
    @report = described_class.new(
      data_path("export_clients_cavegest.xlsx"), sheets: ["Feuil1"], report: MigrationReport.new
    ).call
  end

  after(:all) do
    Customer.delete_all
    PriceGrid.delete_all
  end

  let(:report) { @report }

  it "keeps the leading zero of postal codes" do
    expect(Customer.find_by(reference: "T00022").zip).to eq("01000")
  end

  it "skips the totals row at the bottom of the file" do
    expect(Customer.where(reference: "TOTAL")).to be_empty
  end

  it "stores the shipping address when it differs from the billing one" do
    customer = Customer.find_by(reference: "T00013")

    expect(customer.zip).to eq("04000")
    expect(customer.shipping_zip).to eq("11100")
  end

  it "falls back on the billing address when the shipping one is a copy of it" do
    expect(Customer.find_by(reference: "T00004").use_billing_address).to be(true)
    expect(Customer.find_by(reference: "T00013").use_billing_address).to be(false)
  end

  it "parses the dates stored as text" do
    expect(Customer.find_by(reference: "T00001").creation_date).to eq(Date.new(2013, 7, 22))
  end

  it "deactivates the customers flagged as unusable" do
    expect(Customer.find_by(reference: "T00004").active).to be(false)
  end

  it "completes a postal code when the country is missing" do
    customer = Customer.find_by(reference: "T00018")

    expect(customer.country_code).to be_nil
    expect(customer.zip).to eq("07000")
  end

  it "keeps a Belgian postal code at four digits" do
    customer = Customer.find_by(reference: "T00331")

    expect(customer.country_code).to eq("BE")
    expect(customer.zip).to eq("9000")
  end

  it "converts a country name into its ISO code" do
    expect(Customer.find_by(reference: "T02756").country_code).to eq("DE")
  end

  it "writes every phone in the international format" do
    expect(Customer.find_by(reference: "T00001").phone).to eq("+33278983218")
    expect(Customer.find_by(reference: "T00002").phone).to eq("+33222415817")
    expect(Customer.find_by(reference: "T00002").mobile).to eq("+33628982171")
  end

  it "ignores a phone filled with N/C" do
    expect(Customer.find_by(reference: "T00010").phone).to be_nil
  end

  it "keeps a phone number it cannot validate" do
    expect(Customer.find_by(reference: "T00054").phone).to eq("+33691942083")
  end

  it "ignores an email without a domain" do
    expect(Customer.find_by(reference: "T00016").email).to be_nil
  end

  it "completes an excise number to the SEED format" do
    expect(Customer.find_by(reference: "T00003").excise_number).to eq("FR00097791363")
  end

  it "removes the spaces from a VAT number" do
    expect(Customer.find_by(reference: "T00001").vat_number).to eq("FR69995954011")
  end

  it "keeps a VAT number whose country disagrees with the customer's" do
    customer = Customer.find_by(reference: "T00331")

    expect(customer.country_code).to eq("BE")
    expect(customer.vat_number).to eq("FR20999787108")
  end

  it "maps the family codes to kinds" do
    reseller = Customer.find_by(reference: "T00001")

    expect(reseller.kind).to eq("customer")
    expect(reseller.customer_category).to eq("REVENDEUR")
    expect(Customer.find_by(reference: "T00010").kind).to eq("supplier")
  end

  it "uppercases the customer category" do
    expect(Customer.find_by(reference: "T00002").customer_category).to eq("CLIENT FRANCE")
  end

  it "does not import a row without any name" do
    expect(Customer.find_by(reference: "T00078")).to be_nil
  end

  it "stores a reference that appears twice only once" do
    expect(Customer.where(reference: "T00101").count).to eq(1)
  end

   it "creates nothing on a second run" do
    second = MigrationReport.new
    import = described_class.new(
      data_path("export_clients_cavegest.xlsx"), sheets: ["Feuil1"], report: second
    )

    expect { import.call }.not_to change(Customer, :count)

    expect(second.counters[:customers_created]).to eq(0)
    expect(second.counters[:customers_unchanged]).to eq(4991)
  end

  it "counts what it imported" do
    expect(report.counters[:customers_created]).to eq(4991)
    expect(report.counters[:duplicates_merged]).to eq(3)
    expect(report.counters[:phones_normalized]).to eq(7626)
    expect(report.counters[:phones_placeholder]).to eq(207)
    expect(report.counters[:zips_completed_assumed_country]).to eq(402)
    expect(report.counters[:emails_rejected]).to eq(179)
    expect(report.counters[:excise_numbers_completed]).to eq(570)
    expect(report.counters[:kinds_resellers_as_customers]).to eq(982)
    expect(report.errors.size).to eq(3)
  end

  it "leaves the backup sheet aside" do
    expect(Customer.find_by(reference: "T00001").company_name).to eq("LE VERRE GALANT")
    expect(report.counters[:sheets_left_aside]).to eq(1)
  end

  it "rejects a sheet the file does not hold" do
    other = MigrationReport.new

    described_class.new(data_path("export_clients_cavegest.xlsx"), sheets: ["Feuil2"], report: other).call

    expect(other.counters[:sheets_not_found]).to eq(1)
    expect(other.counters[:customers_created]).to eq(0)
  end

  it "rejects a sheet whose first row is not a header" do
    other = MigrationReport.new

    described_class.new(data_path("export_clients_cavegest.xlsx"), sheets: ["clients"], report: other).call

    expect(other.counters[:headers_not_found]).to eq(1)
    expect(other.counters[:customers_updated]).to eq(0)
  end
end
