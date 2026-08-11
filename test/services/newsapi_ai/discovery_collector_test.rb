require "test_helper"

class NewsapiAi::DiscoveryCollectorTest < ActiveSupport::TestCase
  test "unions three discovery views and preserves per-search ranks" do
    client = FakeClient.new
    result = NewsapiAi::DiscoveryCollector.new(client:).call(
      start_date: Date.new(2026, 8, 8),
      end_date: Date.new(2026, 8, 10),
      count: 50,
      min_articles: 5
    )

    assert_equal 4, result.fetch("unique_event_count")
    assert_equal %w[event-a event-b event-c event-d], result.fetch("events").pluck("uri")
    assert_equal [
      { "search" => "new_by_size", "rank" => 1 },
      { "search" => "active_by_size", "rank" => 2 }
    ], result.fetch("events").first.fetch("discovered_by")
    assert_equal "Thailand", result.fetch("events").first.fetch("country")
    assert_equal "School shooting", result.fetch("events").first.dig("concepts", 0, "label")
    assert_equal %w[new_by_size new_by_date active_by_size], result.fetch("searches").pluck("name")
    assert_equal [ false, false, true ], client.requests.pluck(:reporting_window)
  end

  test "rejects an inverted date window before calling the API" do
    client = FakeClient.new

    assert_raises(ArgumentError) do
      NewsapiAi::DiscoveryCollector.new(client:).call(
        start_date: Date.new(2026, 8, 10),
        end_date: Date.new(2026, 8, 8)
      )
    end
    assert_empty client.requests
  end

  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def search_events(**parameters)
      @requests << parameters
      results = if parameters.fetch(:reporting_window)
        [ event("event-d", "Ongoing event"), event("event-a", "Thailand event") ]
      elsif parameters.fetch(:sort_by) == "date"
        [ event("event-b", "Second event"), event("event-c", "Newest event") ]
      else
        [ event("event-a", "Thailand event"), event("event-b", "Second event") ]
      end
      { "results" => results, "totalResults" => 20, "pages" => 1 }
    end

    private

    def event(uri, title)
      {
        "uri" => uri,
        "title" => { "eng" => title },
        "summary" => { "eng" => "Summary" },
        "eventDate" => "2026-08-09",
        "totalArticleCount" => 100,
        "articleCounts" => { "eng" => 60 },
        "location" => {
          "type" => "place",
          "label" => { "eng" => "Bangkok" },
          "country" => { "label" => { "eng" => "Thailand" } }
        },
        "concepts" => [ { "label" => { "eng" => "School shooting" }, "score" => 50 } ],
        "categories" => [ { "uri" => "news/Politics" } ]
      }
    end
  end
end
