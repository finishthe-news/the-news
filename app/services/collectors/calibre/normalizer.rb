require "pathname"
require "set"
require "time"
require "uri"

module Collectors
  module Calibre
    class Normalizer
      SCHEMA_VERSION = "calibre-article/v1".freeze
      ARTICLE_DATE_FIELDS = {
        "article_published" => [ "published_at", "article_markup", "high" ],
        "feed_published" => [ "published_at", "recipe_feed", "medium" ],
        "article_updated" => [ "source_updated_at", "article_markup", "high" ],
        "feed_updated" => [ "source_updated_at", "recipe_feed", "medium" ]
      }.freeze

      class InvalidRecord < StandardError; end

      def initialize(source:, run_root:, allowed_hosts:)
        @source = source
        @run_root = Pathname(run_root).realpath
        @allowed_hosts = allowed_hosts.to_set
      end

      def call(raw_record)
        record = raw_record.deep_stringify_keys
        validate_identity!(record)

        canonical_url = allowed_http_url!(record.fetch("canonical_url"), "canonical_url")
        requested_url = allowed_http_url!(record.fetch("requested_url"), "requested_url")
        title = normalize_title(record.fetch("title"))
        body_text = normalize_body(read_run_file(record.fetch("body_text_path"), "body_text_path"))
        raise InvalidRecord, "title is blank" if title.blank?
        raise InvalidRecord, "body text is blank" if body_text.blank?

        date_metadata, published_at, source_updated_at = normalize_dates(record.fetch("dates"))
        discovery_updated_at = date_from_metadata(date_metadata, "feed_updated")
        retrieved_at = parse_time(record.dig("acquisition", "retrieved_at"), "acquisition.retrieved_at")
        payload = payload_for(
          record:,
          canonical_url:,
          title:,
          body_text:,
          date_metadata:,
          retrieved_at:
        )

        {
          canonical_url:,
          external_id: canonical_url,
          requested_url:,
          final_url: canonical_url,
          title:,
          body_text:,
          language: record["language"].presence || "en",
          published_at:,
          source_updated_at:,
          discovery_updated_at:,
          retrieved_at:,
          completed_at: retrieved_at,
          http_status: 200,
          content_type: "application/json",
          content_hash: CanonicalJson.sha256("title" => title, "body_text" => body_text),
          payload:,
          document_metadata: document_metadata(record, date_metadata),
          request_headers: {},
          response_headers: {}
        }
      rescue KeyError => error
        raise InvalidRecord, "missing #{error.key}"
      end

      private

      def validate_identity!(record)
        unless record["schema_version"] == SCHEMA_VERSION
          raise InvalidRecord, "unsupported schema_version"
        end
        unless record["source_slug"] == @source.slug
          raise InvalidRecord, "source_slug does not match #{@source.slug}"
        end
      end

      def valid_http_url!(value, field)
        uri = URI.parse(value.to_s)
        return uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?

        raise InvalidRecord, "#{field} must be an HTTP URL"
      rescue URI::InvalidURIError
        raise InvalidRecord, "#{field} must be an HTTP URL"
      end

      def allowed_http_url!(value, field)
        url = valid_http_url!(value, field)
        host = URI.parse(url).host.downcase
        raise InvalidRecord, "#{field} host is not allowed" unless @allowed_hosts.include?(host)

        url
      end

      def validate_run_file(value, field)
        path = Pathname(value.to_s)
        path = @run_root.join(path) unless path.absolute?
        path = path.realpath
        unless path.to_s.start_with?("#{@run_root}#{File::SEPARATOR}")
          raise InvalidRecord, "#{field} is outside the run root"
        end

        path
      rescue Errno::ENOENT
        raise InvalidRecord, "#{field} does not exist"
      end

      def read_run_file(value, field)
        validate_run_file(value, field).read
      end

      def normalize_title(value)
        value.to_s.squish
      end

      def normalize_body(value)
        value.to_s
          .gsub("\r\n", "\n")
          .gsub(/[\t\f\v ]+/, " ")
          .gsub(/ *\n */, "\n")
          .gsub(/\n{3,}/, "\n\n")
          .strip
      end

      def normalize_dates(raw_dates)
        dates = raw_dates.to_h.stringify_keys
        metadata = {}

        ARTICLE_DATE_FIELDS.each do |field, (_target, method, confidence)|
          raw_value = dates[field]
          normalized = parse_optional_time(raw_value, "dates.#{field}")
          metadata[field] = {
            "raw_value" => raw_value,
            "normalized_at" => normalized&.iso8601,
            "method" => raw_value.present? ? method : nil,
            "confidence" => raw_value.present? ? confidence : nil
          }
        end

        published_at = first_date(metadata, "article_published", "feed_published")
        source_updated_at = first_date(metadata, "article_updated", "feed_updated")
        [ metadata, published_at, source_updated_at ]
      end

      def first_date(metadata, *fields)
        value = fields.filter_map { |field| metadata.dig(field, "normalized_at") }.first
        Time.zone.parse(value) if value
      end

      def date_from_metadata(metadata, field)
        value = metadata.dig(field, "normalized_at")
        Time.zone.parse(value) if value
      end

      def parse_optional_time(value, field)
        return if value.blank?

        parse_time(value, field)
      end

      def parse_time(value, field)
        Time.iso8601(value.to_s).in_time_zone
      rescue ArgumentError
        raise InvalidRecord, "#{field} is not a valid time"
      end

      def payload_for(record:, canonical_url:, title:, body_text:, date_metadata:, retrieved_at:)
        {
          "schema_version" => SCHEMA_VERSION,
          "source_slug" => @source.slug,
          "article" => {
            "canonical_url" => canonical_url,
            "title" => title,
            "authors" => Array(record["authors"]),
            "language" => record["language"].presence || "en",
            "section" => record["section"],
            "description" => record["description"],
            "dates" => date_metadata
          },
          "content" => {
            "body_text" => body_text,
            "word_count" => body_text.split.size
          },
          "acquisition" => {
            "requested_url" => record["requested_url"],
            "final_url" => canonical_url,
            "retrieved_at" => retrieved_at.iso8601,
            "collector" => record.dig("acquisition", "collector"),
            "recipe_path" => record.dig("acquisition", "recipe_path"),
            "http_status" => 200,
            "http_receipt_inferred" => true
          }
        }
      end

      def document_metadata(record, date_metadata)
        {
          "authors" => Array(record["authors"]),
          "section" => record["section"],
          "description" => record["description"],
          "date_provenance" => date_metadata
        }.compact
      end
    end
  end
end
