module NameCasing
  module_function

  def upcased(value)
    text(value)&.upcase
  end

  def capitalized(value)
    text(value)&.gsub(/\p{Alpha}+/) { |part| part.capitalize }
  end

  def text(value)
    stripped = value.to_s.strip
    stripped.empty? ? nil : stripped
  end
end