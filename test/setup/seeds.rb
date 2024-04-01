require "active_record"
require "active_support/core_ext/numeric/time"

require_relative "./database"
require_relative "./migrations"
require_relative "./models"

# Seeds.rb or any appropriate seed file

ActiveRecord::Base.transaction do
  # Create Entities for Organisations
  organisation_entities = 20.times.map do |n|
    { name: "Entity #{n}", billing_plan: rand(1..3) }
  end
  Entity.insert_all(organisation_entities)

  # Create Organisations
  organisations = 20.times.map do |n|
    { business_number: "BN#{n}", phone_number: "555-#{n.to_s.rjust(4, "0")}", entity_id: n + 1 }
  end
  Organisation.insert_all(organisations)

  # Create Entities for Users
  user_entities = 100.times.map do |n|
    { name: "User Entity #{n}", billing_plan: rand(1..3) }
  end
  Entity.insert_all(user_entities)

  # Create Searchables for Users and Posts
  searchables = 200.times.map do |n|
    { search_index_string: "Searchable #{n}" }
  end
  Searchable.insert_all(searchables)
  searchable_ids = Searchable.pluck(:id)

  # Assign first 100 searchables to users, the rest to posts
  user_searchables, post_searchables = searchable_ids.each_slice(100).to_a

  # Create Users
  users = 100.times.map do |n|
    {
      email: "user#{n}@example.com",
      username: "user#{n}",
      entity_id: 21 + n, # Assuming Entity IDs for users start after organisations
      organisation_id: (n % 20) + 1, # Ensuring users are evenly distributed across organisations
      searchable_id: user_searchables[n],
      status: [*0..2].sample
    }
  end
  User.insert_all(users)

  # Create Posts
  posts = 100.times.map do |n|
    {
      title: "Post Title #{n}",
      body: "Post Body #{n}",
      user_id: n + 1,
      searchable_id: post_searchables[n]
    }
  end
  Post.insert_all(posts)
end
