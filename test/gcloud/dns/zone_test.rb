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

require "helper"

describe Gcloud::Dns::Zone, :mock_dns do
  # Create a zone object with the project's mocked connection object
  let(:zone_name) { "example-zone" }
  let(:zone_dns) { "example.com." }
  let(:zone_hash) { random_zone_hash zone_name, zone_dns }
  let(:zone) { Gcloud::Dns::Zone.from_gapi zone_hash, dns.connection }
  let(:record_name) { "example.com." }
  let(:record_type) { "A" }
  let(:record_ttl)  { 86400 }
  let(:record_data) { ["1.2.3.4"] }
  let(:soa) { Gcloud::Dns::Record.new "example.com.", "SOA", 18600, "ns-cloud-b1.googledomains.com. dns-admin.google.com. 0 21600 3600 1209600 300" }
  let(:updated_soa) { Gcloud::Dns::Record.new "example.com.", "SOA", 18600, "ns-cloud-b1.googledomains.com. dns-admin.google.com. 1 21600 3600 1209600 300" }

  it "knows its attributes" do
    zone.name.must_equal zone_name
    zone.dns.must_equal zone.dns
    zone.description.must_equal ""
    zone.id.must_equal 123456789
    zone.name_servers.must_equal [ "virtual-dns-1.google.example",
                                   "virtual-dns-2.google.example" ]
    zone.name_server_set.must_be :nil?

    creation_time = Time.new 2015, 1, 1, 0, 0, 0, 0
    zone.created_at.must_equal creation_time
  end

  it "can delete itself" do
    mock_connection.delete "/dns/v1/projects/#{project}/managedZones/#{zone.id}" do |env|
      [200, {"Content-Type" => "application/json"}, ""]
    end

    zone.delete
  end

  it "can forcefuly delete itself" do
    # get all records
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      [200, {"Content-Type" => "application/json"},
       list_records_json(5)]
    end

    # delete non-essential records and update SOA
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 0
      json["deletions"].count.must_equal 5
      [200, {"Content-Type" => "application/json"},
       done_change_json]
    end

    # delete zone call
    mock_connection.delete "/dns/v1/projects/#{project}/managedZones/#{zone.id}" do |env|
      [200, {"Content-Type" => "application/json"}, ""]
    end

    zone.delete force: true
  end

  it "can clear all non-essential records" do
    # get all records
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      [200, {"Content-Type" => "application/json"},
       list_records_json(5)]
    end

    # delete non-essential records and update SOA
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 0
      json["deletions"].count.must_equal 5
      [200, {"Content-Type" => "application/json"},
       done_change_json]
    end

    zone.clear!
  end

  it "finds a change" do
    found_change = "dns-change-1234567890"

    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes/#{found_change}" do |env|
      [200, {"Content-Type" => "application/json"},
       find_change_json(found_change)]
    end

    change = zone.change found_change
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal found_change
  end

  it "returns nil when it cannot find a change" do
    unfound_change = "dns-change-0987654321"

    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes/#{unfound_change}" do |env|
      [404, {"Content-Type" => "application/json"},
       ""]
    end

    change = zone.change unfound_change
    change.must_be :nil?
  end

  def find_change_json change_id
    hash = random_change_hash
    hash["id"] = change_id
    hash.to_json
  end

  it "lists changes" do
    num_changes = 3
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "maxResults"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(num_changes)]
    end

    changes = zone.changes
    changes.size.must_equal num_changes
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "lists changes with max set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end

    changes = zone.changes max: 3
    changes.count.must_equal 3
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    changes.token.wont_be :nil?
    changes.token.must_equal "next_page_token"
  end

  it "lists changes with order set to asc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "ascending"
      env.params.wont_include "maxResults"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end

    changes = zone.changes order: :asc
    changes.count.must_equal 3
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    changes.token.wont_be :nil?
    changes.token.must_equal "next_page_token"
  end

  it "lists changes with order set to desc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "descending"
      env.params.wont_include "maxResults"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end

    changes = zone.changes order: :desc
    changes.count.must_equal 3
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    changes.token.wont_be :nil?
    changes.token.must_equal "next_page_token"
  end

  it "paginates changes" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    first_changes = zone.changes
    first_changes.count.must_equal 3
    first_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    first_changes.token.wont_be :nil?
    first_changes.token.must_equal "next_page_token"

    second_changes = zone.changes token: first_changes.token
    second_changes.count.must_equal 2
    second_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    second_changes.token.must_be :nil?
  end

  it "paginates changes with next? and next" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    first_changes = zone.changes
    first_changes.count.must_equal 3
    first_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    first_changes.next?.must_equal true

    second_changes = first_changes.next
    second_changes.count.must_equal 2
    second_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    second_changes.next?.must_equal false
  end

  it "paginates changes with next? and next and max set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    first_changes = zone.changes max: 3
    first_changes.count.must_equal 3
    first_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    first_changes.next?.must_equal true

    second_changes = first_changes.next
    second_changes.count.must_equal 2
    second_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    second_changes.next?.must_equal false
  end

  it "paginates changes with next? and next and order set to asc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "ascending"
      env.params.wont_include "maxResults"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "ascending"
      env.params.wont_include "maxResults"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    first_changes = zone.changes order: :asc
    first_changes.count.must_equal 3
    first_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    first_changes.next?.must_equal true

    second_changes = first_changes.next
    second_changes.count.must_equal 2
    second_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    second_changes.next?.must_equal false
  end

  it "paginates changes with next? and next and order set to desc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "descending"
      env.params.wont_include "maxResults"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "descending"
      env.params.wont_include "maxResults"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    first_changes = zone.changes order: :desc
    first_changes.count.must_equal 3
    first_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    first_changes.next?.must_equal true

    second_changes = first_changes.next
    second_changes.count.must_equal 2
    second_changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
    second_changes.next?.must_equal false
  end

  it "paginates changes with all" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    changes = zone.changes.all.to_a
    changes.count.must_equal 5
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "paginates changes with all and max set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "sortBy"
      env.params.wont_include "sortOrder"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    changes = zone.changes(max: 3).all.to_a
    changes.count.must_equal 5
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "paginates changes with all and order set to asc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "ascending"
      env.params.wont_include "maxResults"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "ascending"
      env.params.wont_include "maxResults"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    changes = zone.changes(order: :asc).all.to_a
    changes.count.must_equal 5
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "paginates changes with all and order set to desc" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "descending"
      env.params.wont_include "maxResults"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "sortBy"
      env.params["sortBy"].must_equal "changeSequence"
      env.params.must_include "sortOrder"
      env.params["sortOrder"].must_equal "descending"
      env.params.wont_include "maxResults"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(2)]
    end

    changes = zone.changes(order: :desc).all.to_a
    changes.count.must_equal 5
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "paginates changes with all using Enumerator" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "second_page_token")]
    end

    changes = zone.changes.all.take(5)
    changes.count.must_equal 5
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "paginates changes with all with request_limit set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_changes_json(3, "second_page_token")]
    end

    changes = zone.changes.all(request_limit: 1).to_a
    changes.count.must_equal 6
    changes.each { |z| z.must_be_kind_of Gcloud::Dns::Change }
  end

  it "lists records" do
    num_records = 3
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      [200, {"Content-Type" => "application/json"},
       list_records_json(num_records)]
    end

    records = zone.records
    records.size.must_equal num_records
    records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "lists records with name param" do
    num_records = 3
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal record_name
      [200, {"Content-Type" => "application/json"},
       list_records_json(num_records)]
    end

    records = zone.records record_name
    records.size.must_equal num_records
    records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "lists records with name and type params" do
    num_records = 3
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal record_name
      env.params["type"].must_equal record_type
      [200, {"Content-Type" => "application/json"},
       list_records_json(num_records)]
    end

    records = zone.records record_name, record_type
    records.size.must_equal num_records
    records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "lists records with subdomain and type params" do
    num_records = 3
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "www.example.com."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       list_records_json(num_records)]
    end

    records = zone.records "www", "A"
    records.size.must_equal num_records
    records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "paginates records" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(2)]
    end

    first_records = zone.records
    first_records.count.must_equal 3
    first_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    first_records.token.wont_be :nil?
    first_records.token.must_equal "next_page_token"

    second_records = zone.records token: first_records.token
    second_records.count.must_equal 2
    second_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    second_records.token.must_be :nil?
  end

  it "paginates records with next? and next" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(2)]
    end

    first_records = zone.records
    first_records.count.must_equal 3
    first_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    first_records.next?.must_equal true

    second_records = first_records.next
    second_records.count.must_equal 2
    second_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    second_records.next?.must_equal false
  end

  it "paginates records with next? and next and max set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(2)]
    end

    first_records = zone.records max: 3
    first_records.count.must_equal 3
    first_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    first_records.next?.must_equal true

    second_records = first_records.next
    second_records.count.must_equal 2
    second_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
    second_records.next?.must_equal false
  end

  it "loads all records with all" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(2)]
    end

    all_records = zone.records.all.to_a
    all_records.count.must_equal 5
    all_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "paginates records with all and max set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "maxResults"
      env.params["maxResults"].must_equal "3"
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(2)]
    end

    all_records = zone.records(max: 3).all.to_a
    all_records.count.must_equal 5
    all_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "loads all records with all using Enumerator" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "second_page_token")]
    end

    all_records = zone.records.all.take(5)
    all_records.count.must_equal 5
    all_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "loads all records with all with request_limit set" do
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.wont_include "pageToken"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "next_page_token")]
    end
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params.must_include "pageToken"
      env.params["pageToken"].must_equal "next_page_token"
      [200, {"Content-Type" => "application/json"},
       list_records_json(3, "second_page_token")]
    end

    all_records = zone.records.all(request_limit: 1).to_a
    all_records.count.must_equal 6
    all_records.each { |z| z.must_be_kind_of Gcloud::Dns::Record }
  end

  it "can create a record" do
    record = zone.record record_name, record_type, record_ttl, record_data

    record.name.must_equal record_name
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record with a fully domain name when not given one" do
    record = zone.record "example.com", record_type, record_ttl, record_data

    record.name.must_equal "example.com." # it appends "."
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record when given nil for the domain name" do
    record = zone.record nil, record_type, record_ttl, record_data

    record.name.must_equal "example.com."
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record when given an empty string for the domain name" do
    record = zone.record "", record_type, record_ttl, record_data

    record.name.must_equal "example.com."
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record when given '@' for the domain name" do
    record = zone.record "@", record_type, record_ttl, record_data

    record.name.must_equal "example.com."
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record with a qualified name when given only a subdomain" do
    record = zone.record "www", record_type, record_ttl, record_data

    record.name.must_equal "www.example.com."
    record.type.must_equal record_type
    record.ttl.must_equal  record_ttl
    record.data.must_equal record_data
  end

  it "creates a record without changing name when it is a NAPTR record" do
    record = zone.record "1.2.3.4", "NAPTR", 3600, "10 100 \"U\" \"E2U+sip\" \"!^\\+44111555(.+)$!sip:7\\1@sip.example.com!\" ."

    record.name.must_equal "1.2.3.4"
    record.type.must_equal "NAPTR"
    record.ttl.must_equal  3600
    record.data.must_equal ["10 100 \"U\" \"E2U+sip\" \"!^\\+44111555(.+)$!sip:7\\1@sip.example.com!\" ."]
  end

  it "adds and removes records with update" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."
    to_remove = zone.record "example.net.", "A", 18600, "example.org."

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, to_remove)]
    end

    change = zone.update to_add, to_remove
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "returns nil when calling update without any records to change" do
    change = zone.update [], []
    change.must_be :nil?
  end

  it "returns nil when calling update with records that have not changed" do
    a_record = zone.record zone.dns, "A", 18600, "0.0.0.0"
    change = zone.update a_record, a_record
    change.must_be :nil?
  end

  it "only updates the records that have changed" do
    a_record = zone.record zone.dns, "A", 18600, "example.com."
    cname_record = zone.record zone.dns, "CNAME", 86400, "example.com."
    mx_record = zone.record zone.dns, "MX", 86400, ["10 mail.#{zone.dns}",
                                                    "20 mail2.#{zone.dns}"]
    to_add = [a_record, cname_record, mx_record]
    to_remove = to_add.map(&:dup)
    to_remove.first.data = ["example.org."]

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to add and remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.first.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.first.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([to_add.first], [to_remove.first])]
    end

    change = zone.update to_add, to_remove
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.first.name
    change.additions.first.type.must_equal to_add.first.type
    change.additions.first.ttl.must_equal  to_add.first.ttl
    change.additions.first.data.must_equal to_add.first.data
    change.deletions.first.name.must_equal to_remove.first.name
    change.deletions.first.type.must_equal to_remove.first.type
    change.deletions.first.ttl.must_equal  to_remove.first.ttl
    change.deletions.first.data.must_equal to_remove.first.data
  end

  it "adds a record" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 1
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"][1].must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([to_add, updated_soa], soa)]
    end

    change = zone.add "example.net.", "A", 18600, "example.com."
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.additions[1].data.must_equal updated_soa.data
    change.deletions.first.data.must_equal soa.data
  end

  it "adds a record with a subdomain" do
    to_add = zone.record "www.example.com.", "A", 18600, "example.net."

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 1
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"][1].must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([to_add, updated_soa], soa)]
    end

    change = zone.add "www", "A", 18600, "example.net."
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.additions[1].data.must_equal updated_soa.data
    change.deletions.first.data.must_equal soa.data
  end

  it "updates without updating soa" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 1
      json["deletions"].count.must_equal 0
      json["additions"].first.must_equal to_add.to_gapi
      json["deletions"].must_be :empty?
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, [])]
    end

    change = zone.update to_add, skip_soa: true
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.must_be :empty?
  end

  it "updates with an integer for soa_serial" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."
    expected_soa = updated_soa
    expected_soa.data = ["ns-cloud-b1.googledomains.com. dns-admin.google.com. 10 21600 3600 1209600 300"]

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 1
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal expected_soa.to_gapi
      json["deletions"].first.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([to_add, expected_soa], soa)]
    end

    change = zone.update to_add, [], soa_serial: 10
    change.additions[1].data.must_equal expected_soa.data
  end

  it "updates with a lambda for soa_serial" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."
    expected_soa = updated_soa
    expected_soa.data = ["ns-cloud-b1.googledomains.com. dns-admin.google.com. 10 21600 3600 1209600 300"]

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 1
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal expected_soa.to_gapi
      json["deletions"].first.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([to_add, expected_soa], soa)]
    end

    change = zone.update to_add, [], soa_serial: lambda { |sn| sn + 10 }
    change.additions[1].data.must_equal expected_soa.data
  end

  it "removes records by name and type" do
    to_remove = zone.record "example.net.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.net."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 1
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([], to_remove)]
    end

    change = zone.remove "example.net.", "A"
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.must_be :empty?
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "removes records by subdomain name and type" do
    to_remove = zone.record "www.example.com.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "www.example.com."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 1
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([], to_remove)]
    end

    change = zone.remove "www", "A"
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.must_be :empty?
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "replaces records by name and type" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."
    to_remove = zone.record "example.net.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.net."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to add and remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, to_remove)]
    end

    change = zone.replace "example.net.", "A", 18600, "example.com."
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "replaces records by subdomain and type" do
    to_add = zone.record "www.example.com.", "A", 18600, "example.net."
    to_remove = zone.record "www.example.com.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "www.example.com."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to add and remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, to_remove)]
    end

    change = zone.replace "www", "A", 18600, "example.net."
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "modifies records by name and type" do
    to_add = zone.record "example.net.", "A", 18600, "example.com."
    to_remove = zone.record "example.net.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.net."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to add and remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, to_remove)]
    end

    change = zone.modify "example.net.", "A" do |a|
      a.data = ["example.com."]
    end
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "modifies records by subdomain and type" do
    to_add = zone.record "www.example.com.", "A", 18600, "example.net."
    to_remove = zone.record "www.example.com.", "A", 18600, "example.org."

    # The request for the records to remove.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "www.example.com."
      env.params["type"].must_equal "A"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(to_remove)]
    end

    # The request for the SOA record, to update its serial number.
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "SOA"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(soa)]
    end

    # The request to add and remove the records.
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 2
      json["deletions"].count.must_equal 2
      json["additions"].first.must_equal to_add.to_gapi
      json["additions"].last.must_equal updated_soa.to_gapi
      json["deletions"].first.must_equal to_remove.to_gapi
      json["deletions"].last.must_equal soa.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json(to_add, to_remove)]
    end

    change = zone.modify "www", "A" do |a|
      a.data = ["example.net."]
    end
    change.must_be_kind_of Gcloud::Dns::Change
    change.id.must_equal "dns-change-created"
    change.additions.first.name.must_equal to_add.name
    change.additions.first.type.must_equal to_add.type
    change.additions.first.ttl.must_equal  to_add.ttl
    change.additions.first.data.must_equal to_add.data
    change.deletions.first.name.must_equal to_remove.name
    change.deletions.first.type.must_equal to_remove.type
    change.deletions.first.ttl.must_equal  to_remove.ttl
    change.deletions.first.data.must_equal to_remove.data
  end

  it "allows for multiple changes in one update using the DSL" do
    a_to_add = zone.record "example.com.", "A", 18600, "127.0.0.1"
    txt_to_remove = zone.record "example.com.", "TXT", 1, "Hello world!"
    mx_to_add = zone.record "example.com.", "MX", 18600, ["mail1.example.com", "mail2.example.com"]
    mx_to_remove = zone.record "example.com.", "MX", 18600, ["mail1.example.net", "mail2.example.net"]
    cname_to_add = zone.record "www.example.com.", "CNAME", 18600, "example.com."
    cname_to_remove = zone.record "www.example.com.", "CNAME", 360, "example.com."

    # mock the lookup for TXT
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "TXT"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(txt_to_remove)]
    end
    # mock the lookup for MX
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "example.com."
      env.params["type"].must_equal "MX"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(mx_to_remove)]
    end
    # mock the lookup for CNAME
    mock_connection.get "/dns/v1/projects/#{project}/managedZones/#{zone.id}/rrsets" do |env|
      env.params["name"].must_equal "www.example.com."
      env.params["type"].must_equal "CNAME"
      [200, {"Content-Type" => "application/json"},
       lookup_records_json(cname_to_remove)]
    end
    # mock the update call, test that additions and deletions are correct
    mock_connection.post "/dns/v1/projects/#{project}/managedZones/#{zone.id}/changes" do |env|
      json = JSON.parse env.body
      json["additions"].count.must_equal 3
      json["deletions"].count.must_equal 3
      json["additions"].must_include a_to_add.to_gapi
      json["additions"].must_include mx_to_add.to_gapi
      json["additions"].must_include cname_to_add.to_gapi
      json["deletions"].must_include txt_to_remove.to_gapi
      json["deletions"].must_include mx_to_remove.to_gapi
      json["deletions"].must_include cname_to_remove.to_gapi
      [200, {"Content-Type" => "application/json"},
       create_change_json([a_to_add, mx_to_add], [txt_to_remove, mx_to_remove])]
    end

    zone.update skip_soa: true do |tx|
      tx.add "example.com.", "A", 18600, "127.0.0.1"
      tx.remove "example.com.", "TXT"
      tx.replace "example.com.", "MX", 18600, ["mail1.example.com", "mail2.example.com"]
      tx.modify "www.example.com.", "CNAME" do |cname|
        cname.ttl = 18600
      end
    end
  end

  def lookup_records_json record
    hash = { "kind" => "dns#resourceRecordSet", "rrsets" => [record.to_gapi] }
    hash.to_json
  end

  def create_change_json to_add, to_remove
    hash = random_change_hash
    hash["id"] = "dns-change-created"
    hash["additions"] = Array(to_add).map(&:to_gapi)
    hash["deletions"] = Array(to_remove).map(&:to_gapi)
    hash.to_json
  end

  def list_changes_json count = 2, token = nil
    changes = count.times.map do
      ch = random_change_hash
      ch["id"] = "dns-change-#{rand 9999999}"
      ch
    end
    hash = { "kind" => "dns#changesListResponse", "changes" => changes }
    hash["nextPageToken"] = token unless token.nil?
    hash.to_json
  end

  def list_records_json count = 2, token = nil
    seed = rand 99999
    name = "example-#{seed}.com."
    records = count.times.map do
      random_record_hash name, "A", seed, ["1.2.3.4"]
    end
    hash = { "kind" => "dns#resourceRecordSet", "rrsets" => records }
    hash["nextPageToken"] = token unless token.nil?
    hash.to_json
  end
end
