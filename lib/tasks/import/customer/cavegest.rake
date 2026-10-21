namespace :import do
  namespace :customer do
    desc "Importe les clients CaveGest (SHEETS=Feuil1,autre pour choisir les feuilles)"
    task :cavegest do
      sheets = ENV.fetch("SHEETS", "Feuil1").split(",").map(&:strip)

      puts Customer::Import::Cavegest.new(
        File.join(DATA_DIR, "export_clients_cavegest.xlsx"), sheets: sheets
      ).call
    end
  end
end
