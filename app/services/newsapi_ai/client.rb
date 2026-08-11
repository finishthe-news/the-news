require "json"
require "net/http"
require "uri"

module NewsapiAi
  class Client
    BASE_URL = "https://eventregistry.org/api/v1/".freeze
    EVENT_SORTS = %w[date rel size socialScore none].freeze

    class Error < StandardError; end

    Response = Data.define(:status, :body)

    class Transport
      def initialize(open_timeout: 10, read_timeout: 60)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def post(uri, headers:, body:)
        request = Net::HTTP::Post.new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @open_timeout,
          read_timeout: @read_timeout
        ) { |http| http.request(request) }

        Response.new(status: response.code.to_i, body: response.body.to_s)
      end
    end

    def initialize(api_key:, transport: Transport.new)
      raise ArgumentError, "NEWSAPI_AI_KEY is required" if api_key.blank?

      @api_key = api_key
      @transport = transport
    end

    def event_info(event_uri)
      event_result(event_uri, result_type: "info").fetch("info")
    end

    def search_events(
      start_date:,
      end_date:,
      sort_by:,
      count: 50,
      page: 1,
      min_articles: 5,
      reporting_window: false
    )
      raise ArgumentError, "count must be between 1 and 50" unless count.between?(1, 50)
      raise ArgumentError, "page must be positive" unless page.positive?
      raise ArgumentError, "unsupported event sort" unless EVENT_SORTS.include?(sort_by)

      date_parameters = if reporting_window
        { reportingDateStart: start_date.iso8601, reportingDateEnd: end_date.iso8601 }
      else
        { dateStart: start_date.iso8601, dateEnd: end_date.iso8601 }
      end

      post(
        "event/getEvents",
        {
          action: "getEvents",
          resultType: "events",
          eventsPage: page,
          eventsCount: count,
          eventsSortBy: sort_by,
          eventsSortByAsc: false,
          lang: "eng",
          minArticlesInEvent: min_articles,
          includeEventTitle: true,
          includeEventSummary: true,
          includeEventDate: true,
          includeEventLocation: true,
          includeEventArticleCounts: true,
          includeEventConcepts: true,
          includeEventCategories: true,
          includeConceptLabel: true,
          includeCategoryParentUri: true,
          includeLocationCountryContinent: true
        }.merge(date_parameters)
      ).fetch("events")
    rescue KeyError
      raise Error, "NewsAPI.ai did not return events"
    end

    def event_sources(event_uri)
      event_result(
        event_uri,
        result_type: "sourceExAggr",
        includeSourceLocation: true,
        includeLocationCountryContinent: true
      ).fetch("sourceExAggr")
    end

    def event_articles(event_uri, sort_by:, count: 30, source_uris: nil)
      source_filter = if source_uris.present?
        { sourceUri: source_uris, sourceOper: "or" }
      else
        {}
      end
      event_result(
        event_uri,
        result_type: "articles",
        articlesPage: 1,
        articlesCount: count,
        lang: "eng",
        articlesIncludeDuplicates: false,
        articlesSortBy: sort_by,
        articlesSortByAsc: sort_by == "sourceImportanceRank",
        includeArticleTitle: true,
        includeArticleBasicInfo: true,
        includeArticleBody: true,
        articleBodyLen: -1,
        includeArticleEventUri: true,
        includeSourceTitle: true,
        includeSourceLocation: true,
        includeSourceRanking: true,
        includeLocationCountryContinent: true,
        **source_filter
      ).fetch("articles")
    end

    private

    def event_result(event_uri, result_type:, **parameters)
      response = post(
        "event/getEvent",
        {
          action: "getEvent",
          eventUri: event_uri,
          resultType: result_type,
          includeEventTitle: true,
          includeEventDate: true,
          includeEventLocation: true,
          includeEventArticleCounts: true,
          includeEventConcepts: true,
          includeConceptLabel: true
        }.merge(parameters)
      )

      response.fetch(event_uri)
    rescue KeyError
      raise Error, "NewsAPI.ai did not return event #{event_uri}"
    end

    def post(path, payload)
      uri = URI.join(BASE_URL, path)
      response = @transport.post(
        uri,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(payload.merge(apiKey: @api_key))
      )

      unless response.status.between?(200, 299)
        raise Error, "NewsAPI.ai returned HTTP #{response.status}"
      end

      parsed = JSON.parse(response.body)
      raise Error, parsed.fetch("error").to_s if parsed.key?("error")

      parsed
    rescue JSON::ParserError => error
      raise Error, "NewsAPI.ai returned invalid JSON: #{error.message}"
    end
  end
end
