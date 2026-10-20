class MigrationReport
  Issue = Struct.new(:level, :source, :locator, :message, :details, keyword_init: true)

  SEPARATOR = "=" * 60

  LABELS = {
    customers_created: "Clients créés",
    customers_updated: "Clients mis à jour",
    customers_unchanged: "Clients inchangés",
    duplicates_merged: "Doublons fusionnés",

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
    vat_numbers_placeholder: "Numéros de TVA notés « N/C » ou équivalent, non repris",
    vat_numbers_invalid: "Numéros de TVA au format invalide, conservés",

    excise_numbers_completed: "Numéros d'accise complétés au format SEED (13 caractères)",
    excise_numbers_kept: "Numéros d'accise au format inattendu, conservés",
    excise_numbers_placeholder: "Numéros d'accise notés « N/C » ou équivalent, non repris",

    kinds_resellers_as_customers: "Revendeurs repris comme clients (catégorie REVENDEUR conservée)",
    kinds_unknown: "Codes famille client inconnus",
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
    counters.map { |key, value| "#{LABELS.fetch(key, key)} : #{value}" }.join("\n")
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
