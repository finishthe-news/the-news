require "test_helper"

class Collectors::FederalRegisterTest < ActiveSupport::TestCase
  FakeHttpClient = Struct.new(:response, :requests) do
    def get(uri, headers:)
      requests << { uri:, headers: }
      response
    end
  end

  test "collects primary documents with a transparent receipt and is idempotent" do
    source = create_source_with_policy
    response = Collectors::HttpClient::Response.new(
      status: 200,
      body: JSON.generate(
        "count" => 1,
        "total_pages" => 1,
        "results" => [ {
          "document_number" => "2026-12345",
          "title" => "A test rule",
          "type" => "Rule",
          "publication_date" => "2026-08-04",
          "html_url" => "https://www.federalregister.gov/d/2026-12345",
          "pdf_url" => "https://www.govinfo.gov/content/pkg/FR-2026-08-04/pdf/2026-12345.pdf",
          "agencies" => [ { "name" => "Test Agency" } ]
        } ]
      ),
      headers: { "content-type" => "application/json", "server" => "hidden" },
      final_url: "https://www.federalregister.gov/api/v1/documents.json"
    )
    http = FakeHttpClient.new(response, [])
    collector = Collectors::FederalRegister.new(
      source:,
      http_client: http,
      clock: -> { Time.zone.parse("2026-08-04 10:00:00") },
      user_agent: "TheNews/0.1.0 (+https://finishthe.news; mailto:news@example.test)"
    )

    first_run = collector.call(publication_date: Date.new(2026, 8, 4), per_page: 10)
    second_run = collector.call(publication_date: Date.new(2026, 8, 4), per_page: 10)

    assert first_run.status_succeeded?
    assert_equal 1, first_run.documents_created
    assert_equal 1, first_run.snapshots_created
    assert_equal 0, second_run.documents_created
    assert_equal 0, second_run.snapshots_created
    assert_equal 1, source.source_documents.count
    assert_equal 1, DocumentSnapshot.count

    snapshot = DocumentSnapshot.first
    assert_equal source.approved_policy, snapshot.source_policy
    assert_equal "TheNews/0.1.0 (+https://finishthe.news; mailto:news@example.test)", snapshot.collector_identity
    assert_equal({ "content-type" => "application/json" }, snapshot.response_headers)
    assert_equal snapshot.content_hash, Digest::SHA256.hexdigest(CanonicalJson.dump(snapshot.payload))
    assert_includes http.requests.first.fetch(:uri).query, "conditions%5Bpublication_date%5D%5Bgte%5D=2026-08-04"
    assert_equal snapshot.collector_identity, http.requests.first.dig(:headers, "User-Agent")
  end

  private

  def create_source_with_policy
    source = Source.create!(
      name: "Federal Register",
      slug: "federal-register",
      source_type: "primary",
      owner_name: "Office of the Federal Register",
      canonical_url: "https://www.federalregister.gov/",
      active: true
    )
    source.source_policies.create!(
      version: 1,
      status: "approved",
      access_method: "official_json_api",
      endpoint_url: "https://www.federalregister.gov/api/v1/documents.json",
      reviewed_by: "Editor",
      reviewed_at: Time.current,
      content_hash: SecureRandom.hex(32)
    )
    source
  end
end
