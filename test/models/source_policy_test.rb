require "test_helper"

class SourcePolicyTest < ActiveSupport::TestCase
  test "approval requires reviewer and review time" do
    policy = build_policy(status: "approved", reviewed_by: nil, reviewed_at: nil)

    assert_not policy.valid?
    assert_includes policy.errors[:reviewed_by], "is required for an approved policy"
    assert_includes policy.errors[:reviewed_at], "is required for an approved policy"
  end

  test "approved policies are immutable" do
    policy = build_policy(status: "approved", reviewed_by: "Editor", reviewed_at: Time.current)
    policy.save!

    policy.notes = "Changed"

    assert_not policy.save
    assert_includes policy.errors[:base], "approved source policies are immutable; create a new version"
  end

  private

  def build_policy(**attributes)
    SourcePolicy.new({
      source: Source.create!(
        name: "Test source",
        slug: "test-source-#{SecureRandom.hex(4)}",
        source_type: "primary",
        owner_name: "Test owner",
        canonical_url: "https://example.test"
      ),
      version: 1,
      status: "draft",
      access_method: "api",
      endpoint_url: "https://example.test/api",
      content_hash: SecureRandom.hex(32)
    }.merge(attributes))
  end
end
