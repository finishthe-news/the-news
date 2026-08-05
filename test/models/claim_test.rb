require "test_helper"

class ClaimTest < ActiveSupport::TestCase
  test "attributed claims name their source" do
    claim = Claim.new(
      event_cluster: EventCluster.create!(
        title: "Test event",
        first_seen_at: Time.current,
        last_seen_at: Time.current
      ),
      statement: "The agency said the rule will take effect.",
      status: "attributed",
      content_hash: SecureRandom.hex(32)
    )

    assert_not claim.valid?
    assert_includes claim.errors[:attributed_to], "is required for an attributed claim"

    claim.attributed_to = "Test Agency"
    assert claim.valid?
  end
end
