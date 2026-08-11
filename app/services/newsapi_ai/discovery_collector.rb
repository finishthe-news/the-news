module NewsapiAi
  class DiscoveryCollector
    SEARCHES = [
      { "name" => "new_by_size", "sort_by" => "size", "reporting_window" => false },
      { "name" => "new_by_date", "sort_by" => "date", "reporting_window" => false },
      { "name" => "active_by_size", "sort_by" => "size", "reporting_window" => true }
    ].freeze

    def initialize(client:)
      @client = client
    end

    def call(start_date:, end_date:, count: 50, min_articles: 5)
      raise ArgumentError, "start_date must not be after end_date" if start_date > end_date

      events_by_uri = {}
      search_receipts = SEARCHES.map do |search|
        response = @client.search_events(
          start_date:,
          end_date:,
          sort_by: search.fetch("sort_by"),
          count:,
          min_articles:,
          reporting_window: search.fetch("reporting_window")
        )
        response.fetch("results", []).each_with_index do |event, index|
          uri = event.fetch("uri")
          normalized = events_by_uri[uri] ||= normalize_event(event)
          normalized.fetch("discovered_by") << {
            "search" => search.fetch("name"),
            "rank" => index + 1
          }
        end

        {
          "name" => search.fetch("name"),
          "sort_by" => search.fetch("sort_by"),
          "reporting_window" => search.fetch("reporting_window"),
          "returned" => response.fetch("results", []).length,
          "total_results" => response["totalResults"],
          "pages" => response["pages"]
        }
      end

      {
        "window" => {
          "start_date" => start_date.iso8601,
          "end_date" => end_date.iso8601,
          "date_precision" => "calendar_day"
        },
        "minimum_articles" => min_articles,
        "searches" => search_receipts,
        "unique_event_count" => events_by_uri.length,
        "events" => events_by_uri.values
      }
    end

    private

    def normalize_event(event)
      location = event.fetch("location", {}) || {}
      {
        "uri" => event.fetch("uri"),
        "vendor_title" => localized(event["title"]),
        "vendor_summary" => localized(event["summary"]),
        "event_date" => event["eventDate"],
        "location" => localized(location["label"]),
        "country" => location_country(location),
        "all_language_articles" => event["totalArticleCount"],
        "english_articles" => event.dig("articleCounts", "eng"),
        "concepts" => normalize_concepts(event.fetch("concepts", [])),
        "categories" => event.fetch("categories", []).first(5).map { |category| category["uri"] },
        "discovered_by" => []
      }
    end

    def normalize_concepts(concepts)
      concepts.first(10).filter_map do |concept|
        label = localized(concept["label"])
        next if label.blank?

        { "label" => label, "score" => concept["score"] }
      end
    end

    def location_country(location)
      localized(location.dig("country", "label")) ||
        (location["type"] == "country" ? localized(location["label"]) : nil)
    end

    def localized(value)
      value.is_a?(Hash) ? value["eng"] || value.values.first : value
    end
  end
end
