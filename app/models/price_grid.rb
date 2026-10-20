class PriceGrid < ActiveRecord::Base
  validates :code, presence: true, uniqueness: true

  before_validation :normalize_casing

  private

  def normalize_casing
    self[:code] = TextNormalization.upcased(self[:code])
    self[:name] = TextNormalization.upcased(self[:name])
  end
end
