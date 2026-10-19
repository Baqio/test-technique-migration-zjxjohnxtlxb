class MigrationReport
  Issue = Struct.new(:level, :source, :locator, :message, :details, keyword_init: true)

  SEPARATOR = "=" * 60

  LABELS = {
    customers_created: "Clients créés",
    customers_updated: "Clients mis à jour",
    customers_unchanged: "Clients inchangés",
    duplicates_merged: "Doublons fusionnés",
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

    value.to_s.strip.empty? ? "vide" : value.to_s
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

    "#{issue.message} : #{changes.map { |field, (before, after)| "#{field} (#{displayed(before)} → #{displayed(after)})" }.join(', ')}"
  end
end
