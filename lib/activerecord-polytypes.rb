# frozen_string_literal: true

require_relative "activerecord-polytypes/version"

# ActiveRecordPolytypes extends ActiveRecord models with the capability to efficiently fetch, query, and aggregate across collections of subtypes without the need for:
# - Creating wide tables with many nullable columns (Single Table Inheritance).
# - Performing separate queries for each subtype and aggregating or filtering in memory (Abstract Classes, Delegated Types).
# - Encoding type information into data, which can lead to data integrity issues (Delegated Types).
# - Repeating common column definitions and constraints across multiple tables (Abstract Classes).
# - Relying on database-specific features like Postgres' table inheritance.
#
# Imagine you have a simple Entity model that can represent either a User or an Organisation, and it has associated legal documents and a billing plan.
#
#   # An entity, is either a user or an organisation.
#   # It is also a container for a collection of legal documents,
#   # and it has an associated billing plan.
#   class Entity
#     belongs_to :billing_plan
#     has_many :documents
#   end
#
#   class User < ApplicationRecord;end
#   class Organisation < ApplicationRecord;end
#
# At times you may wish to fetch all entities, and their associated documents and billing plans
# but then vary in behaviour or processing, based on the subtype of entity.
#
# What are our options?
#
# == Use a wide table, with a 'type' column with many nullable columns to implement STI. Then add user and organisation specific columns to it. However:
# * With each new type, our table becomes more and more bloated.
# * We leak rigid, code-specific type strings into our database, making it more difficult to shuffle types in the future.
# * Because we use native Ruby inheritance, User and Organisation are strictly coupled to Entity. I.e. they can't also be a subtype of another class.
#
# == Use separate tables for each subtype. Make Entity an abstract class.
# * We now have lean tables, but lose the ability to query across all entities in a single hit (e.g. useful for any operations where we would like to treat subtypes as part of a uniform collection)
# * Because we use native Ruby inheritance, User and Organisation are strictly coupled to Entity. I.e. they can't also be a subtype of another class.
# * We have to repeat common column definitions and constraints across multiple tables, because subtypes no longer share a supertype table.
#
# == Use delegated types, so that we can store superclass specific info on the Entity class, and subclass specific info on the User and Organisation classes.
# * We can query across all entities in a single hit (and also preload subtypes to load these reasonably efficiently)
# * We can allow User and Organisation to be delegated to (i.e. act as subtype to) more than one class.
# * We have a logical home for common column and constraints, and separate homes for subtype specific columns and constraints.
# * But:
# * * We still have to perform separate queries to load subtype details when addressing a collection
# * * We still have to perform aggregations or filters on subtype attributes in memory.
# * * We leak rigid code-specific strings into our database, making it more difficult to shuffle types.
#
# This is where ActiveRecordPolytypes provides an alternative mechanism.
# With ActiveRecordPolytypes you can easily query across all subtypes like this:
#
#   Entity::Subtype.where("user_created_at > ? OR organisation_country IN (?)", 1.day.ago, %(US)).order(billing_plan_renewal_date: :desc)
# To e.g. fetch all entities that are either users created in the last day, or organisations in the US.
# and order by a common attribute:
#   => [
#     #<Entity::User...
#     #<Entity::Organisation...
#     #<Entity::User...
#     #<Entity::User...
#     #<Entity::Organisation...
#
# It constructs the needed joins so that you can query across all subtypes in a single hit, performing aggregations and filters on subtype attributes, directly in the database.
# The instantiated subtypes also provide an interface that combines the interface of joined supertype + subtype.
# E.g. in the above, for each:
# * *Entity::User* object, you can access the full set of methods and attributes from both Entity and User.
# * *Entity::Organisation* object, you can access the full set of methods and attributes from both Entity and User.
#
# You can even create or update supertype + subtype objects in a single hit.
# E.g.
#
#   Entity::User.create(
#     billing_plan_id: 3, # Entity attributes
#     user_name: # User attributes
#   )
#
#   Entity::User.find(1).update(
#     billing_plan_id: 3, # Entity attributes
#     user_name: # User attributes
#   )
#
# You can also limit queries to specific subtypes when applicable
# E.g.
#
# Limit to specific subtypes
#
#   Entity::User.where(user_name: "Bob")
#   Entity::Organisation.where(organisation_country: "US")
#
# Vs query across all subtypes
#
#   Entity::Subtype.where(...)
#
#
# All you need to do to install ActiveRecordPolytypes into an existing model, is make a call to <tt>polymorphic_supertype_of</tt> in the model, and pass in the names of the associations that you want to act as subtypes.
# It will work on any existing <tt>belongs_to</tt> or <tt>has_one</tt> association (respecting any non conventional foreign keys, class overrides etc.)
#
#   class Entity < ApplicationRecord
#     belongs_to :billing_plan
#     has_many :documents
#     belongs_to :user
#     belongs_to :organisation
#     polymorphic_supertype_of :user, :organisation
#   end
#
# An entity can act as a subtype to any number of supertypes, so e.g. while Users and Organisations might act as Entities, within a billing context
# they might also act as SearchableItems within a search API. Inheriting from multiple supertypes is as easy as repeating the pattern above, per supertype.
# E.g.
#
#  class Searchable < ApplicationRecord
#     validates :searchable_index_string, presence: true
#     belongs_to :user
#     belongs_to :post
#     belongs_to :category
#     polymorphic_supertype_of :user, :post, :category
#   end
#
#   Searchable::Subtype.all # => [#<Searchable::User..., #<Searchable::Post.., #<Searchable::Category.., #<Searchable::User..]
#
# @note This documentation and code example is illustrative of how ActiveRecordPolytypes can be integrated into an ActiveRecord model to leverage polymorphism efficiently.
module ActiveRecordPolytypes
  extend ActiveSupport::Concern


  # @!method polymorphic_supertype_of(*associations)
  #   Sets up the ActiveRecord model as a polymorphic supertype of the specified associations
  #   @!scope class
  #   @param associations [Array<Symbol>] the names of the associations that should act as subtypes.
  #     These associations are expected to be either `:belongs_to` or `:has_one` associations.
  #
  #   @example Adding polymorphic supertype to an Entity model
  #     class Entity < ApplicationRecord
  #       belongs_to :billing_plan
  #       has_many :documents
  #       belongs_to :user
  #       belongs_to :organisation
  #       polymorphic_supertype_of :user, :organisation
  #     end
  class_methods do

    def polymorphic_supertype_of(*associations)
      associations = associations.map { |a| reflect_on_association(a) }.compact
      return unless associations.any?

      supertype_type = self
      # Remove any previously defined constant to avoid constant redefinition warnings.
      self.send(:remove_const, :Subtype) if self.constants.include?(:Subtype)

      # Define a new class inherited from the current class acting as the subtype.
      subtype_class = self.const_set(:Subtype, Class.new(self))
      subtype_class.class_eval do

        attribute :type

        select_components_by_type = {}
        case_components_by_type = {}
        join_components_by_type = {}

        # Prepare SQL components to construct a query that joins subtypes and selects their attributes and type.
        associations.each do |association|
          base_type = association.compute_class(association.class_name)

          base_type.reflect_on_all_associations.each do |assoc|
            case assoc.macro
            when :belongs_to
              subtype_class.belongs_to :"#{association.name}_#{assoc.name}", assoc.scope, **assoc.options, class_name: assoc.class_name
            when :has_one, :has_many
              scope = if assoc.options.key?(:as)
                refined = ->{ where(assoc.type => base_type.name) }
                if assoc.scope
                  ->{ instance_exec(&refined).instance_exec(&assoc.scope) }
                else
                  refined
                end
              else
                assoc.scope
              end
              self.send(assoc.macro, :"#{association.name}_#{assoc.name}", scope, **assoc.options.except(:inverse_of, :destroy, :as), primary_key: "#{association.name}_#{base_type.primary_key}", foreign_key: assoc.foreign_key, class_name: "::#{assoc.class_name}")
            end
          end
        end

        associations.each do |association|
          base_type = association.compute_class(association.class_name)
          # Generate a class name for the subtype proxy.
          subtype_class_name = "#{supertype_type.name}::#{base_type.name}"
          # Dynamically create a proxy class for the multi-table inheritance.
          build_mti_proxy_class!(association, base_type, supertype_type, subtype_class)

          select_components_by_type[association.name] = base_type.columns.map do |column|
            column_name = "#{association.name}_#{column.name}"
            "#{association.table_name}.#{column.name} as #{column_name}"
          end.join(",")

          case_components_by_type[association.name] = "WHEN #{association.table_name}.#{association.join_primary_key} IS NOT NULL THEN '#{subtype_class_name}'"
          join_components_by_type[association.name] = if association.belongs_to?
            "LEFT JOIN #{association.table_name} ON #{table_name}.#{association.foreign_key} = #{association.table_name}.#{association.join_primary_key}"
          else
            "LEFT JOIN #{association.table_name} ON #{table_name}.#{association.association_primary_key} = #{association.table_name}.#{association.join_primary_key}"
          end
        end

        # Define a scope `with_subtypes` that enriches the base query with subtype information.
        scope :with_subtypes, ->(*typenames){
          select_components, case_components, join_components = typenames.map do |typename|
            [
              select_components_by_type[typename],
              case_components_by_type[typename],
              join_components_by_type[typename]
            ]
          end.transpose

          from(<<~SQL)
            (
              SELECT #{table_name}.*,#{select_components * ","}, CASE #{case_components * " "} ELSE '#{name}' END AS type
              FROM #{table_name} #{join_components * " "}
            ) #{table_name}
          SQL
        }

        # Automatically apply `with_subtypes` scope to all queries if specified.
        default_scope -> { with_subtypes(*associations.map(&:name)) }
      end
    end

    # Dynamically builds a proxy class for a given association to handle multi-table inheritance.
    def build_mti_proxy_class!(association, base_type, supertype_type, subtype_class)
      # Remove any previously defined constant to avoid constant redefinition warnings.
      supertype_type.send(:remove_const, base_type.name) if supertype_type.constants.include?(base_type.name.to_sym)

      # Define a new class inherited from the current class acting as the subtype.
      subtype_class = supertype_type.const_set(base_type.name, Class.new(subtype_class))
      subtype_class.class_eval do
        attr_reader :inner

        # Only include records of this subtype in the default scope.
        default_scope ->{ with_subtypes(association.name) }
        # Define callbacks and methods for initializing and saving the inner object.
        after_initialize :initialize_inner_object
        before_save :save_inner_object_if_changed
        after_save :reload, if: :previously_new_record?

        # Define attributes and delegation methods for columns inherited from the base type.
        base_type.reflect_on_all_associations.each do |assoc|
          case assoc.macro
          when :belongs_to
            belongs_to assoc.name, assoc.scope, **assoc.options, class_name: assoc.class_name
          when :has_one, :has_many
            scope = if assoc.options.key?(:as)
              refined = ->{ where(assoc.type => base_type.name) }
              if assoc.scope
                ->{ instance_exec(&refined).instance_exec(&assoc.scope) }
              else
                refined
              end
            else
              assoc.scope
            end
            self.send(assoc.macro, assoc.name, scope, **assoc.options.except(:inverse_of, :destroy, :as), primary_key: "#{association.name}_#{base_type.primary_key}", foreign_key: assoc.foreign_key, class_name: "::#{assoc.class_name}")
          end
        end
        base_type.columns.each do |column|
          column_name = "#{association.name}_#{column.name}"
          attribute column_name
          delegate column.name, to: :@inner, allow_nil: true, prefix: association.name
          define_method :"#{column_name}=" do |value|
            case
            when @inner then @inner.send(:"#{column.name}=", value)
            else
              (@assigned_attributes ||= {})[column.name] = value
            end
          end
        end

        # Provide a mechanism to handle methods not explicitly defined in the proxy class, delegating them to the @inner object if possible.
        def method_missing(m, *args, &block)
          if @inner.respond_to?(m)
            @inner.send(m, *args, &block)
          else
            super
          end
        end

        # Initialize the inner object based on the association's attributes or build a new association instance.
        define_method :initialize_inner_object do
          # Prepare attributes for instantiation.
          @inner_attributes ||= base_type.columns.each_with_object({}) do |c, attrs|
            attrs[c.name.to_s] = self["#{association.name}_#{c.name}"]
          end
          # Instantiate or build the inner object based on current record state.
          if @assigned_attributes && @assigned_attributes[association.association_primary_key]
            @inner = base_type.instantiate(association.association_primary_key => @assigned_attributes[association.association_primary_key])
            self.send(:"#{association.name}=", @inner)
            @inner.assign_attributes(@assigned_attributes)
            @assigned_attributes.each do |name, attribute|
              self["#{association.name}_#{name}"] = attribute
            end
          elsif !new_record?
            @inner = base_type.instantiate(@inner_attributes)
          else
            @inner = self.association(association.name).build(@assigned_attributes)
          end
        end

        # Override `as_json` to include attributes from both the outer and inner objects.
        define_method :as_json do |options={}|
          only = base_type.column_names + ["type"] + (options || {}).fetch(:only,[])
          outer = super(**(options || {}), only: )
          @inner.as_json(options).merge(outer)
        end

        # Save the inner object if it has changed before saving the outer object.
        def save_inner_object_if_changed
          @inner.save if @inner.changed?
        end

        # Check if an attribute exists in either the outer or inner object.
        def _has_attribute?(attribute)
          super || @inner._has_attribute?(attribute)
        end

        # Reload both the outer and inner objects to ensure consistency.
        define_method :reload do
          super()
          @inner.reload
          # Update attributes from the reloaded inner object.
          base_type.columns.each_with_object({}) do |c, attrs|
            self["#{association.name}_#{c.name}"] = @inner[c.name.to_s]
          end
          self
        end
      end
    end
  end
end

# Hook into ActiveSupport's on_load mechanism to automatically include this functionality into ActiveRecord.
ActiveSupport.on_load(:active_record) do
  include ActiveRecordPolytypes
end
