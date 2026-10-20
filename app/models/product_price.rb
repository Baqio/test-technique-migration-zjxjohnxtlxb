class ProductPrice < ActiveRecord::Base
  belongs_to :product
  belongs_to :price_grid

  validates :price_grid_id, uniqueness: { scope: :product_id }
  validates :amount_ht, numericality: { greater_than_or_equal_to: 0 }
end
