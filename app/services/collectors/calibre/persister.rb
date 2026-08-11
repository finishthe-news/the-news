require "time"

module Collectors
  module Calibre
    class Persister
      ADAPTER_VERSION = "1".freeze
      DISCOVERY_SCHEMA_VERSION = "calibre-discovery-decision/v1".freeze
      Result = Data.define(
        :documents_seen,
        :documents_created,
        :snapshots_created,
        :observations_created,
        :errors
      )
      class InvalidContext < StandardError; end

      def initialize(
        source:,
        policy:,
        collection_run:,
        run_root:,
        allowed_hosts:,
        clock: -> { Time.current },
        collector_identity: Collectors::CollectorIdentity.value
      )
        @source = source
        @policy = policy
        @collection_run = collection_run
        @clock = clock
        @collector_identity = collector_identity
        validate_context!
        @normalizer = Normalizer.new(source:, run_root:, allowed_hosts:)
      end

      def call(records:, observations: [])
        counts = {
          documents_seen: records.length,
          documents_created: 0,
          snapshots_created: 0,
          observations_created: 0
        }
        errors = []

        records.each_with_index do |record, index|
          persist_record(@normalizer.call(record), counts)
        rescue => error
          errors << error_receipt("article", index, error)
        end

        observations.each_with_index do |observation, index|
          persist_observation(observation, index, counts)
        rescue => error
          errors << error_receipt("observation", index, error)
        end

        Result.new(**counts, errors:)
      end

      private

      def persist_record(record, counts)
        SourceDocument.transaction do
          document = @source.source_documents.find_or_initialize_by(
            canonical_url: record.fetch(:canonical_url)
          )
          new_document = document.new_record?
          document.assign_attributes(
            external_id: record.fetch(:external_id),
            title: record.fetch(:title),
            language: record.fetch(:language),
            published_at: record.fetch(:published_at) || document.published_at,
            source_updated_at: newest_time(
              document.source_updated_at,
              record.fetch(:source_updated_at)
            ),
            discovery_updated_at: newest_time(
              document.discovery_updated_at,
              record.fetch(:discovery_updated_at)
            ),
            metadata: record.fetch(:document_metadata)
          )
          document.save!
          counts[:documents_created] += 1 if new_document

          snapshot = document.document_snapshots.find_or_initialize_by(
            content_hash: record.fetch(:content_hash)
          )
          if snapshot.new_record?
            payload_json = CanonicalJson.dump(record.fetch(:payload))
            snapshot.assign_attributes(
              source_policy: @policy,
              collection_run: @collection_run,
              requested_url: record.fetch(:requested_url),
              final_url: record.fetch(:final_url),
              retrieved_at: record.fetch(:retrieved_at),
              completed_at: record.fetch(:completed_at),
              http_status: record.fetch(:http_status),
              content_type: record.fetch(:content_type),
              collector_identity: @collector_identity,
              adapter_version: ADAPTER_VERSION,
              byte_size: payload_json.bytesize,
              payload: record.fetch(:payload),
              request_headers: record.fetch(:request_headers),
              response_headers: record.fetch(:response_headers)
            )
            snapshot.save!
            counts[:snapshots_created] += 1
          end
        end
      end

      def persist_observation(raw_observation, position, counts)
        observation = raw_observation.deep_stringify_keys
        validate_observation!(observation)
        canonical_url = optional_http_url(observation["canonical_url"])
        document = @source.source_documents.find_by(canonical_url:)

        discovered = @source.discovery_observations.find_or_initialize_by(
          collection_run: @collection_run,
          position:
        )
        return unless discovered.new_record?

        discovered.assign_attributes(
          source_document: document,
          canonical_url:,
          discovered_url: observation["discovered_url"],
          published_at: parse_optional_time(observation["feed_published"]),
          source_updated_at: parse_optional_time(observation["feed_updated"]),
          observed_at: @clock.call,
          metadata: observation.slice(
            "hook",
            "title",
            "feed_published",
            "feed_updated",
            "source_updated_at",
            "known_source_updated_at",
            "decision",
            "reason"
          )
          .merge(
            "date_provenance" => {
              "feed_published" => date_provenance(observation["feed_published"]),
              "feed_updated" => date_provenance(observation["feed_updated"])
            }
          )
        )
        discovered.save!
        counts[:observations_created] += 1
      end

      def validate_observation!(observation)
        unless observation["schema_version"] == DISCOVERY_SCHEMA_VERSION
          raise Normalizer::InvalidRecord, "unsupported discovery schema_version"
        end
        unless observation["source_slug"] == @source.slug
          raise Normalizer::InvalidRecord, "discovery source_slug does not match #{@source.slug}"
        end
        unless %w[fetch skip].include?(observation["decision"])
          raise Normalizer::InvalidRecord, "unsupported discovery decision"
        end
      end

      def validate_context!
        unless @policy.source_id == @source.id &&
            @collection_run.source_id == @source.id &&
            @collection_run.source_policy_id == @policy.id
          raise InvalidContext, "source, policy, and collection run must match"
        end
        unless @policy.status_approved?
          raise InvalidContext, "source policy must be approved"
        end
      end

      def optional_http_url(value)
        return if value.blank?

        uri = URI.parse(value.to_s)
        return uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?

        nil
      rescue URI::InvalidURIError
        nil
      end

      def parse_optional_time(value)
        return if value.blank?

        Time.iso8601(value.to_s).in_time_zone
      rescue ArgumentError
        raise Normalizer::InvalidRecord, "discovery date is not a valid time"
      end

      def date_provenance(raw_value)
        normalized = parse_optional_time(raw_value)
        {
          "raw_value" => raw_value,
          "normalized_at" => normalized&.iso8601,
          "method" => raw_value.present? ? "recipe_feed" : nil,
          "confidence" => raw_value.present? ? "medium" : nil
        }
      end

      def newest_time(current, candidate)
        [ current, candidate ].compact.max
      end

      def error_receipt(kind, index, error)
        {
          "kind" => kind,
          "index" => index,
          "error_class" => error.class.name,
          "error_message" => error.message.to_s.first(500)
        }
      end
    end
  end
end
