module Importer::Normalization
  module_function

  ZIP_LENGTH = { "FR" => 5, "BE" => 4, "DE" => 5 }.freeze

  def text(value)
    return nil if value.nil?

    value.to_s.strip
  end

  def zip(value, country_code = "FR")
    raw = text(value)
    
    return raw if raw.nil?
    return raw unless ZIP_LENGTH[country_code] && raw.match?(/\A\d+\z/)

    raw.rjust(ZIP_LENGTH[country_code], "0")
  end

  def country_code(value)
    value.to_s.strip[0, 2].upcase
  end

  def decimal(value)
    value.to_s.to_f
  end
end
