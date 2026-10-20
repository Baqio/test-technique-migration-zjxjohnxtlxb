class Importer::HeaderMap
  def initialize(header_row)
    @headers = header_row.each_with_index
                         .group_by { |header, _| header }
                         .transform_values { |pairs| pairs.map(&:last) }
  end

  def value(row, header, rank = nil)
    row[position(header, rank)]
  end

  private

  def position(header, rank)
    found = @headers.fetch(header) { raise KeyError, "en-tête absent : #{header.inspect}" }

    return found.fetch(rank) if rank
    return found.first if found.one?

    raise ArgumentError, "#{header.inspect} apparaît #{found.size} fois, précisez le rang"
  end
end