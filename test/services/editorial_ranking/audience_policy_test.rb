require "test_helper"

class EditorialRanking::AudiencePolicyTest < ActiveSupport::TestCase
  test "accepts NewsAPI string continents and normalizes its North America typo" do
    policy = EditorialRanking::AudiencePolicy.new

    assert_equal "audience", policy.classify(
      source("United Kingdom", "Europe"),
      event_country: "Thailand"
    )
    assert_equal "audience", policy.classify(
      source("United States", "Noth America"),
      event_country: "Thailand"
    )
  end

  test "keeps same-country sources local and other regions excluded" do
    policy = EditorialRanking::AudiencePolicy.new

    assert_equal "local", policy.classify(source("Thailand", "Asia"), event_country: "Thailand")
    assert_equal "excluded", policy.classify(source("India", "Asia"), event_country: "Thailand")
  end

  private

  def source(country, continent)
    {
      "location" => {
        "type" => "place",
        "country" => {
          "label" => { "eng" => country },
          "continent" => continent
        }
      }
    }
  end
end
