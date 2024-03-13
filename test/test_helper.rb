# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pry-byebug"
require "active_record"
require "activerecord-polytypes"
require "setup/seeds"

require "minitest/autorun"
require "minitest/around/unit"
require "setup/transactional_test"
require "minitest/reporters"

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]
