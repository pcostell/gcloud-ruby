# Copyright 2016 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helper"
require "gcloud/translate"

Gcloud::Backoff.retries = 10

if ENV["GCLOUD_TEST_TRANSLATE_KEY"]
  # Create shared translate object so we don't create new for each test
  $translate = Gcloud.translate ENV["GCLOUD_TEST_TRANSLATE_KEY"]
else
  puts "No API Key found for the Translate acceptance tests."
end

module Acceptance
  ##
  # Test class for running against a Translate instance.
  # Ensures that there is an active connection for the tests to use.
  #
  # This class can be used with the spec DSL.
  # To do so, add :translate to describe:
  #
  #   describe "My Translate Test", :translate do
  #     it "does a thing" do
  #       your.code.must_be :thing?
  #     end
  #   end
  class TranslateTest < Minitest::Test
    attr_accessor :translate

    ##
    # Setup project based on available ENV variables
    def setup
      @translate = $translate

      refute_nil @translate, "You do not have an active translate to run the tests."

      super
    end

    # Add spec DSL
    extend Minitest::Spec::DSL

    # Register this spec type for when :translate is used.
    register_spec_type(self) do |desc, *addl|
      addl.include? :translate
    end
  end

  def self.run_one_method klass, method_name, reporter
    result = nil
    (1..3).each do |try|
      result = Minitest.run_one_method(klass, method_name)
      break if (result.passed? || result.skipped?)
      puts "Retrying #{klass}##{method_name} (#{try})"
    end
    reporter.record result
  end
end
