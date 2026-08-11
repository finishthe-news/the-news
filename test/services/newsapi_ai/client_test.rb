require "test_helper"

class NewsapiAi::ClientTest < ActiveSupport::TestCase
  FakeTransport = Struct.new(:response, :requests) do
    def post(uri, headers:, body:)
      requests << { uri:, headers:, body: JSON.parse(body) }
      response
    end
  end

  test "searches a bounded English event window with requested metadata" do
    response = NewsapiAi::Client::Response.new(
      status: 200,
      body: JSON.generate("events" => { "results" => [] })
    )
    transport = FakeTransport.new(response, [])
    client = NewsapiAi::Client.new(api_key: "secret", transport:)

    client.search_events(
      start_date: Date.new(2026, 8, 8),
      end_date: Date.new(2026, 8, 10),
      sort_by: "size",
      count: 50,
      min_articles: 5
    )

    request = transport.requests.fetch(0)
    assert_equal "/api/v1/event/getEvents", request.fetch(:uri).path
    assert_equal "2026-08-08", request.dig(:body, "dateStart")
    assert_equal "2026-08-10", request.dig(:body, "dateEnd")
    assert_equal "eng", request.dig(:body, "lang")
    assert_equal 50, request.dig(:body, "eventsCount")
    assert_equal 5, request.dig(:body, "minArticlesInEvent")
    assert request.dig(:body, "includeEventSummary")
    assert_equal "secret", request.dig(:body, "apiKey")
  end

  test "uses reporting dates for ongoing event discovery" do
    response = NewsapiAi::Client::Response.new(
      status: 200,
      body: JSON.generate("events" => { "results" => [] })
    )
    transport = FakeTransport.new(response, [])
    client = NewsapiAi::Client.new(api_key: "secret", transport:)

    client.search_events(
      start_date: Date.new(2026, 8, 8),
      end_date: Date.new(2026, 8, 10),
      sort_by: "size",
      reporting_window: true
    )

    body = transport.requests.fetch(0).fetch(:body)
    assert_equal "2026-08-08", body.fetch("reportingDateStart")
    assert_equal "2026-08-10", body.fetch("reportingDateEnd")
    assert_not body.key?("dateStart")
  end
end
