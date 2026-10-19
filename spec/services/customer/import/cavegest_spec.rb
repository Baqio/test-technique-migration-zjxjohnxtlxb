require "spec_helper"

RSpec.describe Customer::Import::Cavegest do
  let(:report) { MigrationReport.new }
  before { described_class.new(data_path("export_clients_cavegest.xlsx"), report: report).call }

  it"keeps the leading zero of postal codes" do
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

  it "parses the dates stored as text" do
    expect(Customer.find_by(reference: "T00001").creation_date).to eq(Date.new(2013, 7, 22))
  end

  it "deactivates the customers flagged as unusable" do
    expect(Customer.find_by(reference: "T00004").active).to be(false)
  end

  it "falls back on the billing address when the shipping one is a copy of it" do
    expect(Customer.find_by(reference: "T00004").use_billing_address).to be(true)
    expect(Customer.find_by(reference: "T00013").use_billing_address).to be(false)
  end

  it "creates nothing on a second run" do
    expect { described_class.new(data_path("export_clients_cavegest.xlsx")).call }
      .not_to change(Customer, :count)
  end

  it "counts what it imported" do
    expect(report.counters).to eq(customers_created: 4991, duplicates_merged: 3)
    expect(report.errors.size).to eq(3)
  end
end
