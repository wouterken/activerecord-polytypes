class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

class User < ApplicationRecord
  belongs_to :searchable
  belongs_to :entity
  belongs_to :organisation, inverse_of: :organisation
  has_many :posts, inverse_of: :user
end

class Organisation < ApplicationRecord
  belongs_to :entity
  has_many :organisations, inverse_of: :user
end

class Post < ApplicationRecord
  belongs_to :searchable
  belongs_to :user, inverse_of: :post
end

class Entity < ApplicationRecord
  has_one :user
  has_one :organisation
  polymorphic_supertype_of :user, :organisation
end

class Searchable < ApplicationRecord
  has_one :user
  has_one :post
  polymorphic_supertype_of :user, :post
end
