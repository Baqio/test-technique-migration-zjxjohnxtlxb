require "spec_helper"

RSpec.describe Importer::Normalization do
  describe ".text" do
    it "collapses the spacing" do
      expect(described_class.text(" LE   VERRE \n GALANT ")).to eq("LE VERRE GALANT")
    end

    it "reads a whole number that a spreadsheet stored as a float" do
      expect(described_class.text(69002.0)).to eq("69002")
      expect(described_class.text(75.5)).to eq("75.5")
    end

    it "treats a blank cell as nothing" do
      expect(described_class.text("  ")).to be_nil
      expect(described_class.text(nil)).to be_nil
    end
  end

  describe ".capitalized" do
    it "capitalizes every part of a compound name" do
      expect(described_class.capitalized("jean-marc o'neil")).to eq("Jean-Marc O'Neil")
    end
  end

  describe ".placeholder?" do
    it "recognizes how four languages write an empty value" do
      ["N/C", "N/A", "néant", "Inconnu", "non renseigné", "NULL", "k.A.", "n.v.t.", "geen", "-", "??"]
        .each do |value|
          expect(described_class.placeholder?(value)).to be(true), "#{value} should read as empty"
        end
    end

    it "leaves a real value alone" do
      expect(described_class.placeholder?("Lyon")).to be(false)
    end
  end

  describe ".country_code" do
    it "reads a code, a three-letter code or a name" do
      expect(described_class.country_code("FR")).to eq("FR")
      expect(described_class.country_code("FRA")).to eq("FR")
      expect(described_class.country_code("France ")).to eq("FR")
      expect(described_class.country_code("Allemagne")).to eq("DE")
      expect(described_class.country_code("ESPAGNE")).to eq("ES")
    end

    it "does not take Namibia for an empty value" do
      expect(described_class.placeholder?("NA")).to be(true)
      expect(described_class.country_code("NA")).to eq("NA")
    end

    it "gives up on a value it cannot match" do
      expect(described_class.country_code("XYZ")).to be_nil
      expect(described_class.country_code(nil)).to be_nil
    end
  end

  describe ".zip" do
    it "keeps a code that already fits its country" do
      expect(described_class.zip("01000", "FR")).to eq(["01000", :ok])
      expect(described_class.zip("9000", "BE")).to eq(["9000", :ok])
    end

    it "restores the leading zero a spreadsheet dropped" do
      expect(described_class.zip(1000, "FR")).to eq(["01000", :padded])
    end

    it "assumes France when no country is given" do
      expect(described_class.zip("1000", nil)).to eq(["01000", :padded])
    end

    it "removes the spacing of a French code" do
      expect(described_class.zip("75 001", "FR")).to eq(["75001", :ok])
    end

    it "spaces a British code the way the country writes it" do
      expect(described_class.zip("SW1A1AA", "GB")).to eq(["SW1A 1AA", :ok])
    end

    it "signals a country that uses no postal code" do
      expect(described_class.zip("1234", "HK")).to eq(["1234", :unexpected])
    end

    it "keeps what it cannot complete" do
      expect(described_class.zip("ABC", "FR")).to eq(["ABC", :kept])
      expect(described_class.zip("123456789012", "FR")).to eq(["123456789012", :kept])
    end

    it "drops a placeholder" do
      expect(described_class.zip("N/C", "FR")).to eq([nil, :placeholder])
      expect(described_class.zip(nil, "FR")).to eq([nil, :blank])
    end
  end

  describe ".phone" do
    it "writes a valid number in the international format" do
      expect(described_class.phone("02 78 98 32 18", "FR")).to eq(["+33278983218", :normalized])
    end

    it "reads an already international number without being told the country" do
      expect(described_class.phone("+33 6 28 98 21 71", nil)).to eq(["+33628982171", :normalized])
    end

    it "keeps a plausible number it cannot validate, without its spacing" do
      expect(described_class.phone("06.91.94.20.83", "FR")).to eq(["0691942083", :kept])
    end

    it "refuses what is too short to be a number" do
      expect(described_class.phone("12", "FR")).to eq([nil, :rejected])
    end

    it "drops a placeholder" do
      expect(described_class.phone("N/C", "FR")).to eq([nil, :placeholder])
      expect(described_class.phone(nil, "FR")).to eq([nil, :blank])
    end
  end

  describe ".email" do
    it "lowercases the domain and leaves the mailbox untouched" do
      expect(described_class.email("Contact@Domaine.FR")).to eq(["Contact@domaine.fr", :ok])
    end

    it "refuses an address without a mailbox or without a domain" do
      expect(described_class.email("jean")).to eq([nil, :rejected])
      expect(described_class.email("jean@")).to eq([nil, :rejected])
      expect(described_class.email("a b@c.fr")).to eq([nil, :rejected])
    end

    it "accepts a domain without an extension, which is still a valid address" do
      expect(described_class.email("jean@domaine")).to eq(["jean@domaine", :ok])
    end

    it "drops a placeholder" do
      expect(described_class.email("N/C")).to eq([nil, :placeholder])
      expect(described_class.email(nil)).to eq([nil, :blank])
    end
  end

  describe ".vat_number" do
    it "removes the spacing" do
      expect(described_class.vat_number("FR 69 995 954 011", "FR")).to eq(["FR69995954011", :ok])
    end

    it "keeps a number whose country disagrees with the customer's" do
      expect(described_class.vat_number("FR20999787108", "BE")).to eq(["FR20999787108", :mismatch])
    end

    it "keeps a number whose key is wrong, and says so" do
      expect(described_class.vat_number("FR12345", "FR")).to eq(["FR12345", :invalid])
    end

    it "drops a placeholder" do
      expect(described_class.vat_number("N/C", nil)).to eq([nil, :placeholder])
      expect(described_class.vat_number(nil, nil)).to eq([nil, :blank])
    end
  end

  describe ".excise_number" do
    it "completes a truncated number to the SEED format" do
      expect(described_class.excise_number("FR97791363")).to eq(["FR00097791363", :padded])
      expect(described_class.excise_number("fr 977 913 63")).to eq(["FR00097791363", :padded])
    end

    it "leaves a complete number alone" do
      expect(described_class.excise_number("FR00097791363")).to eq(["FR00097791363", :ok])
    end

    it "keeps what does not look like a SEED number" do
      expect(described_class.excise_number("ABCDEFGHIJKLMNOP")).to eq(["ABCDEFGHIJKLMNOP", :kept])
      expect(described_class.excise_number("9779136")).to eq(["9779136", :kept])
    end

    it "drops a placeholder" do
      expect(described_class.excise_number("N/C")).to eq([nil, :placeholder])
    end
  end

  describe ".decimal" do
    it "reads the French decimal separator" do
      expect(described_class.decimal("13,32")).to eq(["13.32".to_d, :ok])
    end

    it "reads a value glued to its unit" do
      expect(described_class.decimal("19,31 EUR")).to eq(["19.31".to_d, :ok])
      expect(described_class.decimal("20%")).to eq(["20".to_d, :ok])
    end

    it "reads a thousands separator written as a space" do
      expect(described_class.decimal("1 234,50")).to eq(["1234.50".to_d, :ok])
    end

    it "refuses a negative value rather than importing it" do
      expect(described_class.decimal("-5")).to eq([nil, :invalid])
    end

    it "refuses what is not a number" do
      expect(described_class.decimal("abc")).to eq([nil, :invalid])
    end

    it "distinguishes an empty cell from an unreadable one" do
      expect(described_class.decimal("")).to eq([nil, :blank])
      expect(described_class.decimal(nil)).to eq([nil, :blank])
    end
  end

  describe ".date" do
    it "reads the French order" do
      expect(described_class.date("22/07/2013")).to eq(Date.new(2013, 7, 22))
      expect(described_class.date("3/4/2013")).to eq(Date.new(2013, 4, 3))
    end

    it "reads a date written year first" do
      expect(described_class.date("2013-07-22")).to eq(Date.new(2013, 7, 22))
      expect(described_class.date("2013/07/22")).to eq(Date.new(2013, 7, 22))
    end

    it "keeps a date a spreadsheet already parsed" do
      expect(described_class.date(Date.new(2020, 1, 1))).to eq(Date.new(2020, 1, 1))
    end

    it "refuses a year on two digits, which does not say whether 13 is the year" do
      expect { described_class.date("22/07/13") }.to raise_error(Date::Error)
    end

    it "refuses a month that cannot be one rather than reading it as a day" do
      expect { described_class.date("07/22/2013") }.to raise_error(Date::Error)
    end

    it "refuses a date written in letters" do
      expect { described_class.date("4 juillet 2013") }.to raise_error(Date::Error)
    end

    it "treats a blank cell as nothing" do
      expect(described_class.date(nil)).to be_nil
      expect(described_class.date("")).to be_nil
    end
  end
end
