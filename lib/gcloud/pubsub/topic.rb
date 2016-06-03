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


require "gcloud/errors"
require "gcloud/pubsub/topic/batch"
require "gcloud/pubsub/topic/list"
require "gcloud/pubsub/subscription"
require "gcloud/pubsub/policy"

module Gcloud
  module Pubsub
    ##
    # # Topic
    #
    # A named resource to which messages are published.
    #
    # @example
    #   require "gcloud"
    #
    #   gcloud = Gcloud.new
    #   pubsub = gcloud.pubsub
    #
    #   topic = pubsub.topic "my-topic"
    #   topic.publish "task completed"
    #
    class Topic
      ##
      # @private The gRPC Service object.
      attr_accessor :service

      ##
      # @private The gRPC Google::Pubsub::V1::Topic object.
      attr_accessor :grpc

      ##
      # @private Create an empty {Topic} object.
      def initialize
        @service = nil
        @grpc = Google::Pubsub::V1::Topic.new
        @name = nil
        @exists = nil
      end

      ##
      # @private New lazy {Topic} object without making an HTTP request.
      def self.new_lazy name, service, options = {}
        new.tap do |t|
          t.grpc = nil
          t.service = service
          t.instance_variable_set "@name", service.topic_path(name, options)
        end
      end

      ##
      # The name of the topic in the form of
      # "/projects/project-identifier/topics/topic-name".
      def name
        @grpc ? @grpc.name : @name
      end

      ##
      # Permanently deletes the topic.
      #
      # @return [Boolean] Returns `true` if the topic was deleted.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   topic.delete
      #
      def delete
        ensure_service!
        service.delete_topic name
        return true
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end

      ##
      # Creates a new {Subscription} object on the current Topic.
      #
      # @param [String] subscription_name Name of the new subscription. Must
      #   start with a letter, and contain only letters ([A-Za-z]), numbers
      #   ([0-9], dashes (-), underscores (_), periods (.), tildes (~), plus (+)
      #   or percent signs (%). It must be between 3 and 255 characters in
      #   length, and it must not start with "goog".
      # @param [Integer] deadline The maximum number of seconds after a
      #   subscriber receives a message before the subscriber should acknowledge
      #   the message.
      # @param [String] endpoint A URL locating the endpoint to which messages
      #   should be pushed.
      #
      # @return [Gcloud::Pubsub::Subscription]
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   sub = topic.subscribe "my-topic-sub"
      #   puts sub.name # => "my-topic-sub"
      #
      # @example The name is optional, and will be generated if not given:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   sub = topic.subscribe "my-topic-sub"
      #   puts sub.name # => "generated-sub-name"
      #
      # @example Wait 2 minutes for acknowledgement and push all to an endpoint:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   sub = topic.subscribe "my-topic-sub",
      #                         deadline: 120,
      #                         endpoint: "https://example.com/push"
      #
      def subscribe subscription_name, deadline: nil, endpoint: nil
        ensure_service!
        options = { deadline: deadline, endpoint: endpoint }
        grpc = service.create_subscription name, subscription_name, options
        Subscription.from_grpc grpc, service
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end
      alias_method :create_subscription, :subscribe
      alias_method :new_subscription, :subscribe

      ##
      # Retrieves subscription by name.
      #
      # @param [String] subscription_name Name of a subscription.
      # @param [Boolean] skip_lookup Optionally create a {Subscription} object
      #   without verifying the subscription resource exists on the Pub/Sub
      #   service. Calls made on this object will raise errors if the service
      #   resource does not exist. Default is `false`.
      #
      # @return [Gcloud::Pubsub::Subscription, nil] Returns `nil` if
      #   the subscription does not exist.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   subscription = topic.subscription "my-topic-subscription"
      #   puts subscription.name
      #
      # @example Skip the lookup against the service with `skip_lookup`:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   # No API call is made to retrieve the subscription information.
      #   subscription = pubsub.subscription "my-sub", skip_lookup: true
      #   puts subscription.name
      #
      def subscription subscription_name, skip_lookup: nil
        ensure_service!
        return Subscription.new_lazy subscription_name, service if skip_lookup
        grpc = service.get_subscription subscription_name
        Subscription.from_grpc grpc, service
      rescue GRPC::BadStatus => e
        return nil if e.code == 5
        raise Error.from_error(e)
      end
      alias_method :get_subscription, :subscription
      alias_method :find_subscription, :subscription

      ##
      # Retrieves a list of subscription names for the given project.
      #
      # @param [String] token The `token` value returned by the last call to
      #   `subscriptions`; indicates that this is a continuation of a call, and
      #   that the system should return the next page of data.
      # @param [Integer] max Maximum number of subscriptions to return.
      #
      # @return [Array<Subscription>] (See {Subscription::List})
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   subscription = topic.subscriptions
      #   subscriptions.each do |subscription|
      #     puts subscription.name
      #   end
      #
      # @example With pagination: (See {Subscription::List#token})
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   all_subs = []
      #   tmp_subs = topic.subscriptions
      #   while tmp_subs.any? do
      #     tmp_subs.each do |subscription|
      #       all_subs << subscription
      #     end
      #     # break loop if no more subscriptions available
      #     break if tmp_subs.token.nil?
      #     # get the next group of subscriptions
      #     tmp_subs = topic.subscriptions token: tmp_subs.token
      #   end
      #
      def subscriptions token: nil, max: nil
        ensure_service!
        options = { token: token, max: max }
        grpc = service.list_topics_subscriptions name, options
        Subscription::List.from_grpc grpc, service
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end
      alias_method :find_subscriptions, :subscriptions
      alias_method :list_subscriptions, :subscriptions

      ##
      # Publishes one or more messages to the topic.
      #
      # @param [String] data The message data.
      # @param [Hash] attributes Optional attributes for the message.
      # @yield [batch] a block for publishing multiple messages in one request
      # @yieldparam [Topic::Batch] batch the batch object
      #
      # @return [Message, Array<Message>] Returns the published message when
      #   called without a block, or an array of messages when called with a
      #   block.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   msg = topic.publish "new-message"
      #
      # @example Additionally, a message can be published with attributes:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   msg = topic.publish "new-message",
      #                       foo: :bar,
      #                       this: :that
      #
      # @example Multiple messages can be sent at the same time using a block:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   msgs = topic.publish do |batch|
      #     batch.publish "new-message-1", foo: :bar
      #     batch.publish "new-message-2", foo: :baz
      #     batch.publish "new-message-3", foo: :bif
      #   end
      #
      def publish data = nil, attributes = {}
        ensure_service!
        batch = Batch.new data, attributes
        yield batch if block_given?
        return nil if batch.messages.count.zero?
        publish_batch_messages batch
      end

      ##
      # Gets the [Cloud IAM](https://cloud.google.com/iam/) access control
      # policy for this topic.
      #
      # @see https://cloud.google.com/pubsub/reference/rpc/google.iam.v1#iampolicy
      #   google.iam.v1.IAMPolicy
      #
      # @param [Boolean] force Force the latest policy to be retrieved from the
      #   Pub/Sub service when `true`. Otherwise the policy will be memoized to
      #   reduce the number of API calls made to the Pub/Sub service. The
      #   default is `false`.
      #
      # @yield [policy] A block for updating the policy. The latest policy will
      #   be read from the Pub/Sub service and passed to the block. After the
      #   block completes, the modified policy will be written to the service.
      # @yieldparam [Policy] policy the current Cloud IAM Policy for this topic
      #
      # @return [Policy] the current Cloud IAM Policy for this topic
      #
      # @example Policy values are memoized to reduce the number of API calls:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #   topic = pubsub.topic "my-topic"
      #
      #   policy = topic.policy # API call
      #   policy_2 = topic.policy # No API call
      #
      # @example Use `force` to retrieve the latest policy from the service:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #   topic = pubsub.topic "my-topic"
      #
      #   policy = topic.policy force: true # API call
      #   policy_2 = topic.policy force: true # API call
      #
      # @example Update the policy by passing a block:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #   topic = pubsub.topic "my-topic"
      #
      #   policy = topic.policy do |p|
      #     p.add "roles/owner", "user:owner@example.com"
      #   end # 2 API calls
      #
      def policy force: nil
        @policy = nil if force || block_given?
        @policy ||= begin
          ensure_service!
          grpc = service.get_topic_policy name
          Policy.from_grpc grpc
        rescue GRPC::BadStatus => e
          raise Error.from_error(e)
        end
        return @policy unless block_given?
        p = @policy.deep_dup
        yield p
        self.policy = p
      end

      ##
      # Updates the [Cloud IAM](https://cloud.google.com/iam/) access control
      # policy for this topic. The policy should be read from {#policy}. See
      # {Gcloud::Pubsub::Policy} for an explanation of the policy `etag`
      # property and how to modify policies.
      #
      # You can also update the policy by passing a block to {#policy}, which
      # will call this method internally after the block completes.
      #
      # @see https://cloud.google.com/pubsub/reference/rpc/google.iam.v1#iampolicy
      #   google.iam.v1.IAMPolicy
      #
      # @param [Policy] new_policy a new or modified Cloud IAM Policy for this
      #   topic
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #   topic = pubsub.topic "my-topic"
      #
      #   policy = topic.policy # API call
      #
      #   policy.add "roles/owner", "user:owner@example.com"
      #
      #   topic.policy = policy # API call
      #
      def policy= new_policy
        ensure_service!
        grpc = service.set_topic_policy name, new_policy.to_grpc
        @policy = Policy.from_grpc grpc
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end

      ##
      # Tests the specified permissions against the [Cloud
      # IAM](https://cloud.google.com/iam/) access control policy.
      #
      # @see https://cloud.google.com/iam/docs/managing-policies Managing
      #   Policies
      #
      # @param [String, Array<String>] permissions The set of permissions to
      #   check access for. Permissions with wildcards (such as `*` or
      #   `storage.*`) are not allowed.
      #
      #   The permissions that can be checked on a topic are:
      #
      #   * pubsub.topics.publish
      #   * pubsub.topics.attachSubscription
      #   * pubsub.topics.get
      #   * pubsub.topics.delete
      #   * pubsub.topics.update
      #   * pubsub.topics.getIamPolicy
      #   * pubsub.topics.setIamPolicy
      #
      # @return [Array<Strings>] The permissions that have access.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #   topic = pubsub.topic "my-topic"
      #   perms = topic.test_permissions "pubsub.topics.get",
      #                                  "pubsub.topics.publish"
      #   perms.include? "pubsub.topics.get" #=> true
      #   perms.include? "pubsub.topics.publish" #=> false
      #
      def test_permissions *permissions
        permissions = Array(permissions).flatten
        permissions = Array(permissions).flatten
        ensure_service!
        grpc = service.test_topic_permissions name, permissions
        grpc.permissions
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end

      ##
      # Determines whether the topic exists in the Pub/Sub service.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   topic.exists? #=> true
      #
      def exists?
        # Always true if we have a grpc object
        return true unless @grpc.nil?
        # If we have a value, return it
        return @exists unless @exists.nil?
        ensure_grpc!
        @exists = !@grpc.nil?
      end

      ##
      # @private
      # Determines whether the topic object was created with an HTTP call.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   pubsub = gcloud.pubsub
      #
      #   topic = pubsub.topic "my-topic"
      #   topic.lazy? #=> false
      #
      def lazy?
        @grpc.nil?
      end

      ##
      # @private New Topic from a Google::Pubsub::V1::Topic object.
      def self.from_grpc grpc, service
        new.tap do |f|
          f.grpc = grpc
          f.service = service
        end
      end

      protected

      ##
      # @private Raise an error unless an active connection to the service is
      # available.
      def ensure_service!
        fail "Must have active connection to service" unless service
      end

      ##
      # Ensures a Google::Pubsub::V1::Topic object exists.
      def ensure_grpc!
        ensure_service!
        return @grpc if @grpc
        @grpc = service.get_topic @name
      rescue GRPC::BadStatus => e
        return nil if e.code == 5
        raise Error.from_error(e)
      end

      ##
      # Call the publish API with arrays of data data and attrs.
      def publish_batch_messages batch
        grpc = service.publish name, batch.messages
        batch.to_gcloud_messages Array(grpc.message_ids)
      rescue GRPC::BadStatus => e
        raise Error.from_error(e)
      end
    end
  end
end
