ActiveRecord::Schema.define do
  enable_extension "plpgsql"

  create_table :price_grids, force: :cascade do |t|
    t.string  :code, null: false
    t.string  :name
    t.boolean :tax_included, null: false, default: false
    t.timestamps

    t.index :code, unique: true
  end

  create_table :customers, force: :cascade do |t|
    t.string  :reference, null: false          # code du client dans CaveGest
    t.string  :company_name
    t.string  :first_name
    t.string  :last_name
    t.string  :address1
    t.string  :city
    t.string  :zip
    t.string  :country_code, limit: 2
    t.string  :phone
    t.string  :mobile
    t.string  :email
    t.string  :kind, null: false, default: "customer"  # customer / supplier / prospect
    t.string  :customer_category
    t.references :price_grid, foreign_key: true
    t.string  :vat_number
    t.string  :excise_number
    t.date    :creation_date
    t.boolean :active, null: false, default: true

    t.boolean :use_billing_address, null: false, default: true
    t.string  :shipping_company_name
    t.string  :shipping_first_name
    t.string  :shipping_last_name
    t.string  :shipping_address1
    t.string  :shipping_city
    t.string  :shipping_zip
    t.string  :shipping_country_code, limit: 2
    t.string  :shipping_phone

    t.timestamps

    t.index :reference, unique: true
    t.index :vat_number
  end

  create_table :product_classifications, force: :cascade do |t|
    t.string  :name, null: false        # section du catalogue : AOP ROUGES, IGP...
    t.integer :position                 # ordre d'apparition dans l'export
    t.timestamps

    t.index :name, unique: true
  end

  create_table :product_colors, force: :cascade do |t|
    t.string :name, null: false        # Rouge, Blanc, Rosé
    t.timestamps

    t.index :name, unique: true
  end

  create_table :products, force: :cascade do |t|
    t.string  :reference, null: false
    t.string  :name, null: false
    t.string  :vintage
    t.references :product_color, foreign_key: true
    t.integer :volume_ml
    t.decimal :vat_rate, precision: 5, scale: 2
    t.integer :stock
    t.references :product_classification, foreign_key: true
    t.timestamps

    t.index :reference, unique: true
  end

  create_table :product_prices, force: :cascade do |t|
    t.references :product, null: false, foreign_key: true
    t.references :price_grid, null: false, foreign_key: true
    t.decimal    :amount_ht, precision: 10, scale: 2, null: false
    t.timestamps

    t.index %i[product_id price_grid_id], unique: true
  end
end
