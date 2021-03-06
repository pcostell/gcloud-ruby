# Copyright 2015 Google Inc. All rights reserved.
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


require "delegate"

module Gcloud
  module Dns
    class Record
      ##
      # Record::List is a special case Array with additional values.
      class List < DelegateClass(::Array)
        ##
        # If not empty, indicates that there are more records that match
        # the request and this value should be passed to continue.
        attr_accessor :token

        ##
        # @private Create a new Record::List with an array of Record instances.
        def initialize arr = []
          super arr
        end

        ##
        # Whether there a next page of records.
        #
        # @return [Boolean]
        #
        # @example
        #   require "gcloud"
        #
        #   gcloud = Gcloud.new
        #   dns = gcloud.dns
        #   zone = dns.zone "example-com"
        #
        #   records = zone.records "example.com."
        #   if records.next?
        #     next_records = records.next
        #   end
        #
        def next?
          !token.nil?
        end

        ##
        # Retrieve the next page of records.
        #
        # @return [Record::List]
        #
        # @example
        #   require "gcloud"
        #
        #   gcloud = Gcloud.new
        #   dns = gcloud.dns
        #   zone = dns.zone "example-com"
        #
        #   records = zone.records "example.com."
        #   if records.next?
        #     next_records = records.next
        #   end
        #
        def next
          return nil unless next?
          ensure_zone!
          @zone.records @name, @type, token: token, max: @max
        end

        ##
        # Retrieves all records by repeatedly loading {#next} until {#next?}
        # returns `false`. Calls the given block once for each record, which is
        # passed as the parameter.
        #
        # An Enumerator is returned if no block is given.
        #
        # This method may make several API calls until all records are
        # retrieved. Be sure to use as narrow a search criteria as possible.
        # Please use with caution.
        #
        # @param [Integer] request_limit The upper limit of API requests to make
        #   to load all records. Default is no limit.
        # @yield [record] The block for accessing each record.
        # @yieldparam [Record] record The record object.
        #
        # @return [Enumerator]
        #
        # @example Iterating each record by passing a block:
        #   require "gcloud"
        #
        #   gcloud = Gcloud.new
        #   dns = gcloud.dns
        #   zone = dns.zone "example-com"
        #   records = zone.records "example.com."
        #
        #   records.all do |record|
        #     puts record.name
        #   end
        #
        # @example Using the enumerator by not passing a block:
        #   require "gcloud"
        #
        #   gcloud = Gcloud.new
        #   dns = gcloud.dns
        #   zone = dns.zone "example-com"
        #   records = zone.records "example.com."
        #
        #   all_names = records.all.map do |record|
        #     record.name
        #   end
        #
        # @example Limit the number of API calls made:
        #   require "gcloud"
        #
        #   gcloud = Gcloud.new
        #   dns = gcloud.dns
        #   zone = dns.zone "example-com"
        #   records = zone.records "example.com."
        #
        #   records.all(request_limit: 10) do |record|
        #     puts record.name
        #   end
        #
        def all request_limit: nil
          request_limit = request_limit.to_i if request_limit
          unless block_given?
            return enum_for(:all, request_limit: request_limit)
          end
          results = self
          loop do
            results.each { |r| yield r }
            if request_limit
              request_limit -= 1
              break if request_limit < 0
            end
            break unless results.next?
            results = results.next
          end
        end

        ##
        # @private New Records::List from a response object.
        def self.from_response resp, zone, name = nil, type = nil, max = nil
          records = new(Array(resp.data["rrsets"]).map do |gapi_object|
            Record.from_gapi gapi_object
          end)
          records.instance_variable_set "@token", resp.data["nextPageToken"]
          records.instance_variable_set "@zone",  zone
          records.instance_variable_set "@name",  name
          records.instance_variable_set "@type",  type
          records.instance_variable_set "@max",   max
          records
        end

        protected

        ##
        # Raise an error unless an active connection is available.
        def ensure_zone!
          fail "Must have active connection" unless @zone
        end
      end
    end
  end
end
