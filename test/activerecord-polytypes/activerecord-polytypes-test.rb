# frozen_string_literal: true

require "test_helper"

class ActiveRecordPolytypesTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ActiveRecordPolytypes::VERSION
  end

  def test_that_it_defines_new_supertype_classes
    assert Searchable::Subtype.is_a?(Class)
    assert Entity::Subtype.is_a?(Class)
  end

  def test_you_can_query_several_types_in_a_single_scope
    assert(Entity::Subtype.all.any? { |r| r.is_a?(Entity::User) })
    assert(Entity::Subtype.all.any? { |r| r.is_a?(Entity::Organisation) })

    assert(Searchable::Subtype.all.any? { |r| r.is_a?(Searchable::User) })
    assert(Searchable::Subtype.all.any? { |r| r.is_a?(Searchable::Post) })
  end

  def test_you_can_query_combined_attributes_on_subtypes_and_supertypes
    matching_subtypes = Entity::Subtype.where(
      "billing_plan BETWEEN ? AND ? AND (user_username = ? OR organisation_business_number = ? )",
      1,
      3,
      "user1",
      "BN2"
    )
    assert matching_subtypes.all? do |st|
      (st.is_a?(Entity::User) && st.username == "user1") ||
        (st.is_a?(Entity::Organisation) && st.business_number == "BN2")
    end
  end

  def test_a_subtype_can_belong_to_multiple_supertypes
    assert_equal \
      Entity::Subtype.find_by(user_username: "user1").inner,
      Searchable::Subtype.find_by(user_username: "user1").inner
  end

  def test_a_subtype_delegates_to_its_inner
    User.define_method(:username_length) { username.length }

    assert_equal \
      Entity::Subtype.find_by(user_username: "user1").username_length,
      Entity::Subtype.find_by(user_username: "user1").inner.username_length
  end

  def test_that_you_can_query_for_just_subtypes
    assert(Entity::User.all.all? { |r| r.is_a?(Entity::User) })
    assert(Entity::User.all.none? { |r| r.is_a?(Entity::Organisation) })

    assert(Searchable::User.all.all? { |r| r.is_a?(Searchable::User) })
    assert(Searchable::User.all.none? { |r| r.is_a?(Searchable::Post) })
  end

  def test_it_can_create_a_subtype_and_parent_type_simultaneously
    searchable_count = Searchable.count
    user_count = User.count
    user = Searchable::User.create!(
      search_index_string: "Steven King",
      user_email: "steven@king.com",
      user_username: "@sk"
    )
    assert_equal [Searchable.count, User.count], [searchable_count.succ, user_count.succ]
  end

  def test_it_can_update_a_subtype_and_parent_type_simultaneously
    user = Searchable::User.first.update!(
      search_index_string: "Steven King",
      user_email: "steven@king.com",
      user_username: "@sk"
    )
    assert_equal \
      Searchable::User.first.slice(:search_index_string, :user_email, :user_username).values,
      ["Steven King", "steven@king.com", "@sk"]
  end

  def test_you_can_eager_load_subtype_relationships
    assert Searchable::User.eager_load(:posts).all? { |u| u.posts.loaded? }
  end

  def test_you_can_preload_subtype_relationships
    assert Searchable::Subtype.preload(:user_posts).all? { |s| s.user_posts.loaded? }
  end

  def test_you_can_eager_load_subtype_relationships
    assert Searchable::Subtype.eager_load(:user_posts).all? { |s| s.user_posts.loaded? }
  end

  def test_you_can_preload_subtype_relationships_on_subtypes
    assert Searchable::User.preload(:posts).all? { |u| u.posts.loaded? }
  end

  def test_you_can_eager_load_subtype_relationships_on_subtypes
    assert Searchable::User.eager_load(:posts).all? { |u| u.posts.loaded? }
  end


end
