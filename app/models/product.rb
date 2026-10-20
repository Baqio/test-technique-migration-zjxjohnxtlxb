class Product < ActiveRecord::Base
  has_many :product_prices, dependent: :destroy
  belongs_to :product_classification, optional: true
  belongs_to :product_color, optional: true

  validates :reference, presence: true, uniqueness: true
  validates :name, presence: true
end
