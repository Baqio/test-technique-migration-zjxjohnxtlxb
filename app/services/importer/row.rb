class Importer::Row
  attr_reader :locator

  def initialize(cells, locator, map = nil)
    @cells   = cells
    @locator = locator
    @map     = map
  end

  def value(header, rank = nil)
    @map ? @map.value(@cells, header, rank) : @cells[header]
  end
end
