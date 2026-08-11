module EditorialRanking
  class ClusterDossier
    ARTICLE_SAMPLE_COUNT = 30
    MAX_EVIDENCE_ARTICLES = 6
    MAX_LOCAL_ARTICLES = 2
    MIN_BODY_WORDS = 150

    def initialize(client:, audience_policy: AudiencePolicy.new)
      @client = client
      @audience_policy = audience_policy
    end

    def call(event_uri:)
      info = @client.event_info(event_uri)
      source_aggregate = @client.event_sources(event_uri)
      important_articles = @client.event_articles(
        event_uri,
        sort_by: "sourceImportanceRank",
        count: ARTICLE_SAMPLE_COUNT
      )
      representative_articles = @client.event_articles(
        event_uri,
        sort_by: "cosSim",
        count: ARTICLE_SAMPLE_COUNT
      )
      event_country = location_country(info.fetch("location", {}))
      coverage = normalize_coverage(info, source_aggregate, event_country)
      local_source_uris = coverage.fetch("eligible_sources").filter_map do |source|
        source.fetch("domain") if source.fetch("role") == "local"
      end
      local_articles = if local_source_uris.any?
        @client.event_articles(
          event_uri,
          sort_by: "cosSim",
          count: ARTICLE_SAMPLE_COUNT,
          source_uris: local_source_uris
        )
      else
        { "results" => [] }
      end

      {
        "event" => normalize_event(event_uri, info, event_country),
        "coverage" => coverage,
        "concepts" => normalize_concepts(info.fetch("concepts", [])),
        "evidence" => select_evidence(
          important_articles.fetch("results"),
          representative_articles.fetch("results"),
          local_articles.fetch("results"),
          event_country
        )
      }
    end

    private

    def normalize_event(event_uri, info, event_country)
      {
        "uri" => event_uri,
        "vendor_title" => localized(info["title"]),
        "event_date" => info["eventDate"],
        "location" => localized(info.dig("location", "label")),
        "country" => event_country
      }
    end

    def normalize_coverage(info, aggregate, event_country)
      sources = aggregate.fetch("results", []).map do |item|
        source = item.fetch("source")
        {
          "title" => source["title"],
          "domain" => source["uri"],
          "country" => @audience_policy.country_name(source),
          "role" => @audience_policy.classify(source, event_country:),
          "article_count" => item.fetch("counts", []).sum { |daily| daily.fetch("count", 0) }
        }
      end
      eligible = sources.reject { |source| source.fetch("role") == "excluded" }
      dates = aggregate.fetch("results", []).flat_map do |item|
        item.fetch("counts", []).map { |daily| daily["date"] }
      end.compact

      {
        "all_language_articles" => info["totalArticleCount"],
        "english_articles" => info.dig("articleCounts", "eng"),
        "source_sample_size" => sources.length,
        "eligible_publishers_in_sample" => eligible.map { |source| source.fetch("domain") }.uniq.length,
        "local_publishers_in_sample" => eligible.count { |source| source.fetch("role") == "local" },
        "audience_publishers_in_sample" => eligible.count { |source| source.fetch("role") == "audience" },
        "coverage_start" => dates.min,
        "coverage_end" => dates.max,
        "eligible_sources" => eligible
      }
    end

    def normalize_concepts(concepts)
      concepts.first(10).filter_map do |concept|
        label = localized(concept["label"])
        next if label.blank?

        { "label" => label, "score" => concept["score"] }
      end
    end

    def select_evidence(important, representative, local_articles, event_country)
      candidates = unique_articles(local_articles + important + representative).filter_map do |article|
        normalize_article(article, event_country)
      end
      sufficiently_long, short = candidates.partition do |article|
        article.fetch("body_words") >= MIN_BODY_WORDS
      end
      ordered = sufficiently_long + short
      by_source = ordered.each_with_object({}) do |article, result|
        result[article.fetch("domain")] ||= article
      end.values
      local = by_source.select { |article| article.fetch("source_role") == "local" }
      audience = by_source.select { |article| article.fetch("source_role") == "audience" }

      selected = local.first(MAX_LOCAL_ARTICLES)
      selected.concat(audience.first(MAX_EVIDENCE_ARTICLES - selected.length))
      selected.first(MAX_EVIDENCE_ARTICLES)
    end

    def unique_articles(articles)
      articles.index_by { |article| article.fetch("uri") }.values
    end

    def normalize_article(article, event_country)
      source = article.fetch("source", {})
      role = @audience_policy.classify(source, event_country:)
      return if role == "excluded"

      body = article["body"].to_s.strip
      return if body.blank?

      words = body.scan(/\S+/).length
      {
        "uri" => article["uri"],
        "title" => article["title"],
        "url" => article["url"],
        "published_at" => article["dateTimePub"] || article["dateTime"],
        "source" => source["title"],
        "domain" => source["uri"],
        "source_country" => @audience_policy.country_name(source),
        "source_role" => role,
        "body" => body,
        "body_words" => words,
        "completeness" => completeness(article["url"], body, words)
      }
    end

    def completeness(url, body, words)
      return "live_page" if url.to_s.include?("/live/")
      return "insufficient" if words < MIN_BODY_WORDS
      return "provisional" if body.match?(/developing story/i)

      "substantial"
    end

    def location_country(location)
      location.dig("country", "label", "eng") ||
        (location["type"] == "country" ? localized(location["label"]) : nil)
    end

    def localized(value)
      value.is_a?(Hash) ? value["eng"] || value.values.first : value
    end
  end
end
