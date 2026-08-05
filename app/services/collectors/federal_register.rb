require "digest"
require "json"
require "uri"

module Collectors
  class FederalRegister
    ADAPTER_NAME = "federal_register".freeze
    ADAPTER_VERSION = "1".freeze
    SAFE_RESPONSE_HEADERS = %w[
      content-type
      etag
      last-modified
      retry-after
      x-ratelimit-limit
      x-ratelimit-remaining
    ].freeze

    class FetchError < StandardError; end
    class MissingApprovedPolicy < StandardError; end

    def initialize(
      source: Source.find_by!(slug: "federal-register"),
      http_client: HttpClient.new,
      clock: -> { Time.current },
      user_agent: CollectorIdentity.value
    )
      @source = source
      @http_client = http_client
      @clock = clock
      @user_agent = user_agent
    end

    def call(publication_date: Date.current, per_page: 100)
      policy = @source.approved_policy
      raise MissingApprovedPolicy, @source.slug unless policy

      run = CollectionRun.create!(
        source: @source,
        source_policy: policy,
        adapter_name: ADAPTER_NAME,
        adapter_version: ADAPTER_VERSION,
        started_at: @clock.call
      )

      collect(run:, policy:, publication_date:, per_page:)
    rescue => error
      fail_run(run, error) if run&.persisted?
      raise
    end

    private

    def collect(run:, policy:, publication_date:, per_page:)
      uri = build_uri(policy.endpoint_url, publication_date:, per_page:)
      request_started_at = @clock.call
      response = @http_client.get(uri, headers: { "User-Agent" => @user_agent })
      request_completed_at = @clock.call

      unless response.status.between?(200, 299)
        raise FetchError, "Federal Register returned HTTP #{response.status}"
      end

      body = JSON.parse(response.body)
      results = body.fetch("results")
      counts = { documents_created: 0, snapshots_created: 0 }

      results.each do |item|
        persist_document(
          item:,
          run:,
          policy:,
          request_url: uri.to_s,
          response:,
          request_started_at:,
          request_completed_at:,
          counts:
        )
      end

      run.update!(
        status: "succeeded",
        finished_at: @clock.call,
        documents_seen: results.length,
        documents_created: counts.fetch(:documents_created),
        snapshots_created: counts.fetch(:snapshots_created),
        metadata: {
          "api_count" => body["count"],
          "api_total_pages" => body["total_pages"],
          "publication_date" => publication_date.iso8601
        }.compact
      )
      run
    end

    def build_uri(endpoint_url, publication_date:, per_page:)
      uri = URI(endpoint_url)
      uri.query = URI.encode_www_form(
        "per_page" => per_page,
        "order" => "newest",
        "conditions[publication_date][gte]" => publication_date.iso8601,
        "conditions[publication_date][lte]" => publication_date.iso8601
      )
      uri
    end

    def persist_document(
      item:,
      run:,
      policy:,
      request_url:,
      response:,
      request_started_at:,
      request_completed_at:,
      counts:
    )
      document = @source.source_documents.find_or_initialize_by(
        external_id: item.fetch("document_number")
      )
      counts[:documents_created] += 1 if document.new_record?
      document.assign_attributes(
        canonical_url: item.fetch("html_url"),
        title: item.fetch("title"),
        document_type: item["type"],
        published_at: parse_publication_date(item["publication_date"]),
        metadata: document_metadata(item)
      )
      document.save!

      payload_json = CanonicalJson.dump(item)
      snapshot = document.document_snapshots.find_or_initialize_by(
        content_hash: Digest::SHA256.hexdigest(payload_json)
      )
      return unless snapshot.new_record?

      snapshot.assign_attributes(
        source_policy: policy,
        collection_run: run,
        requested_url: request_url,
        final_url: response.final_url,
        retrieved_at: request_started_at,
        completed_at: request_completed_at,
        http_status: response.status,
        content_type: response.headers["content-type"],
        etag: response.headers["etag"],
        last_modified: response.headers["last-modified"],
        collector_identity: @user_agent,
        adapter_version: ADAPTER_VERSION,
        byte_size: payload_json.bytesize,
        payload: item,
        request_headers: { "user-agent" => @user_agent },
        response_headers: response.headers.slice(*SAFE_RESPONSE_HEADERS)
      )
      snapshot.save!
      counts[:snapshots_created] += 1
    end

    def document_metadata(item)
      {
        "abstract" => item["abstract"],
        "agencies" => item["agencies"],
        "citation" => item["citation"],
        "pdf_url" => item["pdf_url"],
        "raw_text_url" => item["raw_text_url"]
      }.compact
    end

    def parse_publication_date(value)
      return if value.blank?

      Time.zone.parse(value)
    end

    def fail_run(run, error)
      run.update_columns(
        status: "failed",
        finished_at: @clock.call,
        error_class: error.class.name,
        error_message: error.message.to_s.first(2_000),
        updated_at: @clock.call
      )
    end
  end
end
