class MigrationReport
  Issue = Struct.new(:level, :source, :locator, :message, :details, keyword_init: true)

  SEPARATOR = "=" * 60

  LABELS = {
    customers_in_base: "Clients en base",
    products_in_base: "Produits en base",
    product_prices_in_base: "Tarifs en base",
    price_grids_in_base: "Grilles tarifaires en base",
    product_classifications_in_base: "Sections du catalogue en base",
    product_colors_in_base: "Couleurs en base",

    customers_created: "Clients créés",
    customers_updated: "Clients mis à jour",
    customers_unchanged: "Clients inchangés",
    duplicates_merged: "Doublons fusionnés",
    customer_duplicate_references: "Références utilisées par deux clients différents",

    countries_unknown: "Pays non reconnus, non repris",

    phones_normalized: "Téléphones convertis au format international",
    phones_kept: "Téléphones conservés après nettoyage (numéro non reconnu)",
    phones_rejected: "Téléphones illisibles, non repris",
    phones_placeholder: "Téléphones notés « N/C » ou équivalent, non repris",

    zips_completed: "Codes postaux complétés (pays connu)",
    zips_completed_assumed_country: "Codes postaux complétés (pays supposé FR)",
    zips_kept: "Codes postaux conservés tels quels (format non conforme)",
    zips_unexpected: "Codes postaux dans un pays qui n'en utilise pas",
    zips_placeholder: "Codes postaux notés « N/C » ou équivalent, non repris",

    emails_rejected: "Adresses e-mail invalides, non reprises",
    emails_placeholder: "Adresses e-mail notées « N/C » ou équivalent, non reprises",

    vat_numbers_country_mismatch: "Numéros de TVA incohérents avec le pays",
    vat_numbers_invalid: "Numéros de TVA au format invalide, conservés",
    vat_numbers_placeholder: "Numéros de TVA notés « N/C » ou équivalent, non repris",

    excise_numbers_completed: "Numéros d'accise complétés au format SEED (13 caractères)",
    excise_numbers_kept: "Numéros d'accise au format inattendu, conservés",
    excise_numbers_placeholder: "Numéros d'accise notés « N/C » ou équivalent, non repris",

    kinds_resellers_as_customers: "Revendeurs repris comme clients (catégorie REVENDEUR conservée)",
    kinds_unknown: "Codes famille client inconnus",

    price_grids_created: "Grilles tarifaires créées",
    price_grids_updated: "Grilles tarifaires mises à jour",
    price_grids_unchanged: "Grilles tarifaires inchangées",
    price_grid_labels_conflicting: "Grilles tarifaires avec des libellés contradictoires",
    price_grid_columns_unknown: "Colonnes de l'export non reprises",
    price_grid_columns_missing: "Grilles tarifaires absentes de l'export",
    price_grids_without_prices: "Grilles tarifaires sans aucun tarif",
    price_grids_without_customers: "Grilles tarifaires sans aucun client",

    products_without_prices: "Produits sans aucun tarif",
    products_without_vat_rate: "Produits sans taux de TVA",
    product_prices_not_positive: "Tarifs à zéro ou négatifs",
    customers_without_price_grid: "Clients sans grille tarifaire",
    price_grids_incomplete: "Grilles tarifaires incomplètes",
    products_possibly_duplicated: "Produits de même désignation et même contenance",
    products_without_volume: "Produits sans contenance",
    products_without_color: "Produits sans couleur",

    product_classifications_created: "Sections du catalogue créées",

    product_colors_created: "Couleurs créées",

    products_created: "Produits créés",
    products_updated: "Produits mis à jour",
    products_unchanged: "Produits inchangés",
    products_without_classification: "Produits hors section du catalogue",
    product_duplicate_references: "Références utilisées par deux produits différents",
    product_sections_incomplete: "Sections dont l'effectif ne correspond pas au sous-total annoncé",

    product_volumes_missing: "Contenants absents",
    product_volumes_unreadable: "Contenants illisibles, volume non repris",
    product_vat_rates_missing: "Taux de TVA illisibles, non repris",
    product_stocks_missing: "Stocks illisibles, non repris",

    product_prices_created: "Tarifs créés",
    product_prices_updated: "Tarifs mis à jour",
    product_prices_unchanged: "Tarifs inchangés",
    product_prices_invalid: "Tarifs illisibles, non repris",
    product_prices_without_vat_rate: "Tarifs TTC sans taux de TVA, non repris",
  }.freeze

  attr_reader :issues, :counters, :title

  def initialize(title: "Rapport de reprise")
    @title    = title
    @issues   = []
    @counters = Hash.new(0)
  end

  def count(key, by = 1)
    @counters[key.to_sym] += by
  end

  def warn(source:, locator:, message:, **details)
    add(:warning, source, locator, message, details)
  end

  def error(source:, locator:, message:, **details)
    add(:error, source, locator, message, details)
  end

  def errors   = issues.select { |issue| issue.level == :error }
  def warnings = issues.select { |issue| issue.level == :warning }

  def to_s
    body = [counters_lines]
    body << section("Erreurs", errors) if errors.any?
    body << section("Avertissements", warnings) if warnings.any?

    [SEPARATOR, title, SEPARATOR, body.join("\n\n"), SEPARATOR].join("\n")
  end

  private

  def add(level, source, locator, message, details)
    @issues << Issue.new(level: level, source: source, locator: locator,
                         message: message, details: details)
  end

  def displayed(value)
    return value.strftime("%d/%m/%Y") if value.is_a?(Date)

    value.to_s.match?(/\A\p{Space}*\z/) ? "vide" : value.to_s
  end

  def counters_lines
    counters.sort_by { |key, _| LABELS.keys.index(key) || LABELS.size }
            .map { |key, value| "#{LABELS.fetch(key, key)} : #{value}" }
            .join("\n")
  end

  def section(title, issues)
    lines = issues.map { |issue| "  #{issue.source} · #{issue.locator} — #{message_for(issue)}" }
    ["#{title} : #{issues.size}", *lines].join("\n")
  end

  def message_for(issue)
    changes = issue.details[:changes]
    return issue.message unless changes

    "#{issue.message} : #{changes.map { |field, (before, after)| "#{field} (#{displayed(before)} -> #{displayed(after)})" }.join(', ')}"
  end
end
