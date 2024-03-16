# ActiveRecord Polytypes

ActiveRecord Polytypes adds features to ActiveRecord to combinine the best of multiple inheritance, multi-table inheritance, and polymorphic relationships, without the need for schema changes. It supports PostgreSQL, MySQL and SQLite.

## Features

- Efficient Polymorphic Queries: Load a polymorphic list of subtypes with a single query, eliminating the need for multiple database hits.
- Intuitive Query Capabilities: Leverage ordinary ActiveRecord queries to filter across supertype and subtype attributes in a single query.
- Schema-Friendly: Integrates into existing ActiveRecord relationships without requiring schema changes.
- Enjoy the benefits of STI, while avoiding wide, sparse tables
- Enjoy the benefits of abstract classes, without giving up the ability to query subtypes in a single collection
- Enjoy the benefits of delegated types, while supporting filtering, ordering and aggregating on subtype and supertype attributes simultaneously and without needing to infiltrate your data with typename strings.

## Anti-goals

- Creating wide tables with many nullable columns (Single Table Inheritance).
- Performing separate queries for each subtype and aggregating or filtering in memory (Abstract Classes, Delegated Types).
- Encoding type information into data, which can lead to data integrity issues (Delegated Types).
- Repeating common column definitions and constraints across multiple tables (Abstract Classes).
- Relying on database-specific features like Postgres' table inheritance.

Install the gem and add to the application's Gemfile by executing:

    $ bundle add activerecord-polytypes

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install activerecord-polytypes

## Rationale

Imagine you have a simple Entity model that can be either a User or an Organisation, and it has associated legal documents and a billing plan.

```ruby
# An entity, is either a user or an organisation.
# It is also a container for a collection of legal documents,
# and it has an associated billing plan.
class Entity
  belongs_to :billing_plan
  has_many :documents
end

class User < ApplicationRecord; end
class Organisation < ApplicationRecord; end
```

At times you may wish to fetch all entities, and their associated documents and billing plans
but then vary in behaviour or processing, based on the subtype of entity.

What are our options?

## 1. Use a wide table, with a 'type' column with many nullable columns to implement STI. Then add user and organisation specific columns to it. However:

- With each new type, our table becomes more and more bloated.
- We leak rigid, code-specific type strings into our database, making it more difficult to shuffle types in the future.
- Because we use native Ruby inheritance, User and Organisation are strictly coupled to Entity. I.e. they can't also be a subtype of another class.

## 2. Use separate tables for each subtype. Make Entity an abstract class.

- We now have lean tables, but lose the ability to query across all entities in a single hit (e.g. useful for any operations where we would like to treat subtypes as part of a uniform collection)
- Because we use native Ruby inheritance, User and Organisation are strictly coupled to Entity. I.e. they can't also be a subtype of another class.
- We have to repeat common column definitions and constraints across multiple tables, because subtypes no longer share a supertype table.

## 3. Use delegated types, so that we can store superclass specific info on the Entity class, and subclass specific info on the User and Organisation classes.

- We can query across all entities in a single hit (and also preload subtypes to load these reasonably efficiently)
- We can allow User and Organisation to be delegated to (i.e. act as subtype to) more than one class.
- We have a logical home for common column and constraints, and separate homes for subtype specific columns and constraints.
- But:
- - We still have to perform separate queries to load subtype details when addressing a collection
- - We still have to perform aggregations or filters on subtype attributes in memory.
- - We leak rigid code-specific strings into our database, making it more difficult to shuffle types.

# Use ActiveRecordPolytypes as an alternative mechanism.

With ActiveRecordPolytypes you can easily query across all subtypes like this:

```ruby
  Entity::Subtype.where("user_created_at > ? OR organisation_country IN (?)", 1.day.ago, %(US)).order(billing_plan_renewal_date: :desc)
```

To e.g. fetch all entities that are either users created in the last day, or organisations in the US.
and order by a common attribute:

```ruby
  => [
    #<Entity::User...
    #<Entity::Organisation...
    #<Entity::User...
    #<Entity::User...
    #<Entity::Organisation...
```

It constructs the needed joins so that you can query across all subtypes in a single hit, performing aggregations and filters on subtype attributes, directly in the database.
The instantiated subtypes also provide an interface that combines supertype + subtype.
E.g. in the above, for each:

- _Entity::User_ object, you can access the full set of methods and attributes from both Entity and User.
- _Entity::Organisation_ object, you can access the full set of methods and attributes from both Entity and User.

You can also create or update supertype + subtype objects in a single hit.
E.g.

```ruby
  Entity::User.create(
    billing_plan_id: 3, # Entity attributes
    user_name: # User attributes
  )
  Entity::User.find(1).update(
    billing_plan_id: 3, # Entity attributes
    user_name: # User attributes
  )
```

You can also limit queries (which limit the joined tables) to specific subtypes when applicable.
E.g.
Limit to specific subtypes

```ruby
  Entity::User.where(user_name: "Bob")
  Entity::Organisation.where(organisation_country: "US")
```

Vs query across all subtypes

```ruby
  Entity::Subtype.where(...)
```

## Usage

All you need to do to install ActiveRecordPolytypes into an existing model, is make a call to `polymorphic_supertype_of` in the model, and pass in the names of the associations that you want to act as subtypes.
It will work on any existing `belongs_to` or `has_one` association (respecting any non conventional foreign keys, class overrides etc.)

```ruby
  class Entity < ApplicationRecord
    belongs_to :billing_plan
    has_many :documents
    belongs_to :user
    belongs_to :organisation
    polymorphic_supertype_of :user, :organisation
  end
```

An entity can act as a subtype to any number of supertypes, so e.g. while Users and Organisations might act as Entities, within a billing context
they might also act as SearchableItems within a search API. Inheriting from multiple supertypes is as easy as repeating the pattern above, per supertype.
E.g.

```ruby
class Searchable < ApplicationRecord
  validates :searchable_index_string, presence: true
  belongs_to :user
  belongs_to :post
  belongs_to :category
  polymorphic_supertype_of :user, :post, :category
end

Searchable::Subtype.all # => [#<Searchable::User..., #<Searchable::Post.., #<Searchable::Category.., #<Searchable::User..]
```

Subtypes also inherit the relationships of their supertypes, so you can even eager or preload these. E.g.

On the parent type

```ruby
# Load the user_posts relation for all users. Empty for non users
# Load the organisation_documents relation for all organisations. Empty for non organisations
assert Entity::Subtype.preload(:user_posts, :organisation_documents).all? { |s| s.user_posts.loaded? && s.organisation_documents.loaded? }
assert Entity::Subtype.eager_load(:user_posts, :organisation_documents).all? { |s| s.user_posts.loaded? && s.organisation_documents.loaded? }
```

On the subtype

```ruby
# Load the user_posts relation for all users. Empty for non users
assert Entity::User.preload(:posts).all? { |s| s.posts.loaded? }
assert Entity::User.eager_load(:posts).all? { |s| s.posts.loaded? }
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/wouterken/activerecord-polytypes. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/wouterken/activerecord-polytypes/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Activerecord::Mti project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/wouterken/activerecord-polytypes/blob/master/CODE_OF_CONDUCT.md).
