class CreateSeedData < ActiveRecord::Migration[5.0]
  def change
    create_table :entities do |t|
      t.string :name
      t.integer :billing_plan
      t.timestamps
    end

    create_table :searchables do |t|
      t.string :search_index_string
    end

    create_table :users do |t|
      t.string :email
      t.string :username
      t.references :entity
      t.references :searchable
      t.references :organisation
      t.integer :status
      t.timestamps
    end

    create_table :organisations do |t|
      t.string :business_number
      t.string :phone_number
      t.references :entity
      t.string :timestamps
    end

    create_table :posts do |t|
      t.string :title
      t.string :body
      t.belongs_to :user
      t.belongs_to :searchable
    end
  end
end

CreateSeedData.migrate("up")
