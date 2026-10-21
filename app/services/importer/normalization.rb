module Importer::Normalization
  module_function

  DEFAULT_COUNTRY = "FR".freeze
  # Garde-fou de la boucle de complétion : le plus long format purement
  # numérique fait 7 chiffres (Portugal), 10 laisse de la marge.
  MAX_ZIP_LENGTH  = 10

  # Valeurs qui veulent dire « vide » (FR, NL, DE, EN).
  # Ne pas utiliser sur le pays : NA = Namibie, NC = Nouvelle-Calédonie.
  PLACEHOLDERS = %r{\A(
    n[/.]?[ac]                                    # N/A, N/C
    | n[ée]ant | inconnue? | ras | aucune?        # FR
    | non[\s-]*(renseign|communiqu)[ée]e?s?
    | none | null | nil | unknown | tbd | tba     # EN
    | not\s*(provided|available|applicable|specified|known)
    | n\.?v\.?t\.? | onbekend | geen              # NL
    | niet\s*(bekend|opgegeven|van\s*toepassing)
    | [ko]\.?\s*a\.?                              # DE
    | unbekannt | keine?r? | entf[äa]llt
    | nicht\s*(angegeben|vorhanden|bekannt)
    | [-?./]+                                     # -, ?, ...
  )\z}ix

  # Numéro d'accise SEED : code pays (2 lettres) + 11 caractères,
  # complété par des zéros à gauche. 13 caractères au total.
  # https://ec.europa.eu/taxation_customs/dds2/seed/
  EXCISE_LENGTH = 13
  EXCISE_FORMAT = /\A[A-Z]{2}[A-Z0-9]{11}\z/
  EXCISE_PARTIAL = /\A[A-Z]{2}[A-Z0-9]{1,10}\z/

  # Unité parfois collée au nombre : « 19,31 EUR », « 20% ».
  UNIT = /\s*(EUR|€|%)\z/i

  DATE_FORMATS = {
    %r{\A\d{1,2}/\d{1,2}/\d{4}\z} => "%d/%m/%Y",
    /\A\d{4}-\d{1,2}-\d{1,2}\z/ => "%Y-%m-%d",
    %r{\A\d{4}/\d{1,2}/\d{1,2}\z} => "%Y/%m/%d"
  }.freeze

  def text(value) = TextNormalization.text(value)
  def upcased(value) = TextNormalization.upcased(value)
  def capitalized(value) = TextNormalization.capitalized(value)

  def placeholder?(value)
    raw = text(value)

    !raw.nil? && raw.match?(PLACEHOLDERS)
  end

  def country_code(value)
    raw = text(value)
    return nil unless raw

    country = ISO3166::Country.find_country_by_alpha2(raw.upcase) ||
              ISO3166::Country.find_country_by_alpha3(raw.upcase) ||
              ISO3166::Country.find_country_by_any_name(raw)

    country&.alpha2
  end

  # [statut] : :ok, :blank, :padded, :kept, :unexpected, :placeholder
  def zip(value, country_code = nil)
    return [nil, :placeholder] if placeholder?(value)

    raw = text(value)&.upcase
    return [nil, :blank] if raw.nil?

    country = country_code || DEFAULT_COUNTRY
    return [raw, :unexpected] unless postal_code?(country)

    # ValidatesZipcode::Zipcode n'admet pas «75 001»
    digits = raw.delete(" ")
    raw = digits if digits.match?(/\A\d+\z/)
    return [formatted_zip(raw, country), :ok] if valid_zip?(raw, country)

    if raw.match?(/\A\d+\z/)
      padded = raw
      padded = "0#{padded}" until padded.size >= MAX_ZIP_LENGTH || valid_zip?(padded, country)
      return [formatted_zip(padded, country), :padded] if valid_zip?(padded, country)
    end

    [raw, :kept]
  end

  # [statut] : :normalized, :blank, :kept, :rejected, :placeholder
  def phone(value, country_code = nil)
    return [nil, :placeholder] if placeholder?(value)

    raw = text(value)
    return [nil, :blank] if raw.nil?

    parsed = Phonelib.parse(raw, country_code || DEFAULT_COUNTRY)
    return [parsed.e164, :normalized] if parsed.valid?

    return [raw.gsub(/[\s.]/, ""), :kept] if parsed.possible?

    [nil, :rejected]
  end

  # [statut] : :ok, :blank, :rejected, :placeholder
  def email(value)
    return [nil, :placeholder] if placeholder?(value)

    raw = text(value)
    return [nil, :blank] if raw.nil?

    local, at, domain = raw.rpartition("@")
    address = at.empty? ? raw : "#{local}@#{domain.downcase}"
    return [address, :ok] if address.match?(URI::MailTo::EMAIL_REGEXP)

    [nil, :rejected]
  end

  # [statut] : :ok, :blank, :invalid, :mismatch, :placeholder
  def vat_number(value, country_code = nil)
    return [nil, :placeholder] if placeholder?(value)

    raw = text(value)&.upcase&.gsub(/[^A-Z0-9]/, "")
    return [nil, :blank] if raw.nil?

    vat = Valvat.new(raw)
    return [raw, :invalid] unless vat.valid?
    return [raw, :mismatch] if country_code && vat.iso_country_code != country_code

    [raw, :ok]
  end

  # [statut] : :ok, :blank, :padded, :kept, :placeholder
  def excise_number(value)
    return [nil, :placeholder] if placeholder?(value)

    raw = text(value)&.upcase&.gsub(/[^A-Z0-9]/, "")
    return [nil, :blank] if raw.nil?
    return [raw, :ok] if raw.match?(EXCISE_FORMAT)
    return [raw, :kept] unless raw.match?(EXCISE_PARTIAL)

    ["#{raw[0, 2]}#{raw[2..].rjust(EXCISE_LENGTH - 2, '0')}", :padded]
  end

  # [statut] : :ok, :blank, :invalid
  def decimal(value)
    raw = text(value)
    return [nil, :blank] if raw.nil?

    digits = raw.sub(UNIT, "").delete(" ").tr(",", ".")
    return [nil, :invalid] unless digits.match?(/\A\d+(\.\d+)?\z/)

    [digits.to_d, :ok]
  end

  def date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)

    raw = text(value)
    format = DATE_FORMATS.find { |shape, _| raw.match?(shape) }&.last
    raise Date::Error, "format de date inconnu : #{raw}" if format.nil?

    Date.strptime(raw, format)
  end

  def postal_code?(country_code)
    @postal_codes ||= {}
    @postal_codes.fetch(country_code) do
      @postal_codes[country_code] = ISO3166::Country.new(country_code)&.postal_code || false
    end
  end

  def valid_zip?(value, country_code)
    ValidatesZipcode::Zipcode.new(zipcode: value, country_alpha2: country_code).valid?
  end

  # Normalise l'espacement : "SW1A1AA" => "SW1A 1AA"
  def formatted_zip(value, country_code)
    ValidatesZipcode::Zipcode.new(zipcode: value, country_alpha2: country_code).format
  end

  private_class_method :postal_code?, :valid_zip?, :formatted_zip
end
