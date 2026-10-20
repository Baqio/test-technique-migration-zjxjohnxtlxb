class ProductClassification < ActiveRecord::Base
  has_many :products

  validates :name, presence: true, uniqueness: true

  before_validation :normalize_casing

  private

  def normalize_casing
    self[:name] = TextNormalization.upcased(self[:name])
  end
end

