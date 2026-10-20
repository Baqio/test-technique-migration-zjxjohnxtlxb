class Customer < ActiveRecord::Base
  KINDS = %w[customer supplier prospect].freeze

  UPCASED = %i[
    company_name
    last_name
    shipping_company_name
    shipping_last_name
    price_grid_code
    customer_category
  ].freeze
  CAPITALIZED = %i[first_name shipping_first_name].freeze

  validates :reference, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validate  :name_present

  before_validation :normalize_casing

  private

  def normalize_casing
    UPCASED.each { |attr| self[attr] = NameCasing.upcased(self[attr]) }
    CAPITALIZED.each { |attr| self[attr] = NameCasing.capitalized(self[attr]) }
  end

  def name_present
    return if company_name.present? || first_name.present? || last_name.present?

    errors.add(:base, "ni raison sociale, ni nom, ni prénom")
  end
end
