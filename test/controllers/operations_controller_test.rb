require "test_helper"

class OperationsControllerTest < ActionDispatch::IntegrationTest
  test "shows a read-only operations dashboard without article bodies" do
    source = Source.create!(
      slug: "the-marshall-project",
      name: "The Marshall Project",
      owner_name: "The Marshall Project",
      source_type: "public_reporting",
      canonical_url: "https://www.themarshallproject.org/",
      active: true
    )
    source.source_policies.create!(
      version: 1,
      status: "approved",
      access_method: "public_rss_and_html",
      endpoint_url: "https://www.themarshallproject.org/rss/recent",
      reviewed_by: "Robert Ritz",
      reviewed_at: Time.current,
      content_hash: SecureRandom.hex(32)
    )

    get root_path

    assert_response :success
    assert_select "h1", "Collection operations"
    assert_select "td", text: /The Marshall Project/
    assert_select ".read-only-badge", "Read only"
    assert_no_match(/body_text/, response.body)
  end
end
