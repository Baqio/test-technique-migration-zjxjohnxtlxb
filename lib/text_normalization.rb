module TextNormalization
  module_function

  def text(value)
    value = value.to_i if value.is_a?(Float) && value.to_i == value

    cleaned = value.to_s.gsub(/\p{Space}+/, " ").strip
    cleaned.empty? ? nil : cleaned
  end

  def upcased(value)
    text(value)&.upcase
  end

  def capitalized(value)
    text(value)&.gsub(/\p{Alpha}+/) { |part| part.capitalize }
  end
end
