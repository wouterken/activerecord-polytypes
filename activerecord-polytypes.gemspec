# frozen_string_literal: true

require_relative "lib/activerecord-polytypes/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-polytypes"
  spec.version = ActiveRecordPolytypes::VERSION
  spec.authors = ["Wouter Coppieters"]
  spec.email = ["wc@pico.net.nz"]

  spec.summary = "Enable ActiveRecord models to act like Polymorphic supertypes."
  spec.description = "This gem provides an extension to ActiveRecord, enabling efficient Multi-Table, Multiple-Inheritance for ActiveRecord models."
  spec.homepage = "https://github.com/wouterken/activerecord-polytypes"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/wouterken/activerecord-polytypes"
  spec.metadata["changelog_uri"] = "https://github.com/wouterken/activerecord-polytypes"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "activerecord", "~>7", ">7"
  spec.add_development_dependency "minitest", "~>5.16"
  spec.add_development_dependency "minitest-around", "0.4.1"
  spec.add_development_dependency "minitest-reporters", "~> 1.1", ">= 1.1.0"
  spec.add_development_dependency "mysql2", "~> 0.5"
  spec.add_development_dependency "pg", "~> 1", "> 1.0"
  spec.add_development_dependency "pry-byebug", "~> 3.0"
  spec.add_development_dependency "sqlite3", "~> 1.3"
end
