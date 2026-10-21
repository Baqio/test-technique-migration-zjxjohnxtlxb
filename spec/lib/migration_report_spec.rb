require "spec_helper"

RSpec.describe MigrationReport do
  subject(:report) { described_class.new(title: "Reprise : essai") }

  describe "#count" do
    it "counts one by default and adds up" do
      report.count(:customers_created)
      report.count(:customers_created)

      expect(report.counters[:customers_created]).to eq(2)
    end

    it "takes the number to add" do
      report.count(:customers_created, 4991)

      expect(report.counters[:customers_created]).to eq(4991)
    end

    it "accepts a key written as a string" do
      report.count("customers_updated")

      expect(report.counters[:customers_updated]).to eq(1)
    end

    it "publishes a control that found nothing" do
      report.count(:products_without_prices, 0)

      expect(report.to_s).to include("Produits sans aucun tarif : 0")
    end
  end

  describe "#to_s" do
    it "names the report between two separators" do
      expect(report.to_s.lines.first(3).map(&:chomp))
        .to eq([described_class::SEPARATOR, "Reprise : essai", described_class::SEPARATOR])
    end

    it "names the report even when no title is given" do
      expect(described_class.new.to_s).to include("Rapport de reprise")
    end

    it "orders the counters as the labels are declared, not as they were counted" do
      report.count(:products_without_prices)
      report.count(:customers_created)

      expect(report.to_s).to include("Clients créés : 1\nProduits sans aucun tarif : 1")
    end

    it "falls back on the key itself when no label exists, and sends it to the end" do
      report.count(:inattendu)
      report.count(:customers_created)

      expect(report.to_s).to include("Clients créés : 1\ninattendu : 1")
    end

    it "says nothing about errors or warnings when there are none" do
      report.count(:customers_created)

      expect(report.to_s).not_to include("Erreurs")
      expect(report.to_s).not_to include("Avertissements")
    end

    it "gives each issue its source and its place in the file" do
      report.error(source: "fichier.xlsx", locator: "Feuil1 ligne 14", message: "refusé")

      expect(report.to_s).to include("Erreurs : 1\n  fichier.xlsx · Feuil1 ligne 14 — refusé")
    end

    it "counts the issues it lists" do
      2.times { |i| report.warn(source: "f.xlsx", locator: "ligne #{i}", message: "à vérifier") }

      expect(report.to_s).to include("Avertissements : 2")
    end

    it "spells out what an update changed" do
      report.warn(source: "f.xlsx", locator: "ligne 13", message: "T00001 mis à jour",
                  changes: { "city" => ["Lyon", "Paris"] })

      expect(report.to_s).to include("T00001 mis à jour : city (Lyon -> Paris)")
    end

    it "writes an empty value as « vide » and a date the French way" do
      report.warn(source: "f.xlsx", locator: "ligne 13", message: "T00001 mis à jour",
                  changes: { "creation_date" => [nil, Date.new(2013, 7, 22)] })

      expect(report.to_s).to include("creation_date (vide -> 22/07/2013)")
    end
  end

  describe "#errors and #warnings" do
    it "separates the two levels" do
      report.error(source: "f", locator: "l", message: "refusé")
      report.warn(source: "f", locator: "l", message: "à vérifier")

      expect(report.errors.map(&:message)).to eq(["refusé"])
      expect(report.warnings.map(&:message)).to eq(["à vérifier"])
    end

    it "keeps them in the order the file was read" do
      report.warn(source: "f", locator: "ligne 2", message: "a")
      report.warn(source: "f", locator: "ligne 9", message: "b")

      expect(report.warnings.map(&:locator)).to eq(["ligne 2", "ligne 9"])
    end
  end
end
