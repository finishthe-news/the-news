require "uri"

module EditorialRanking
  class LocalClusterDossier
    MAX_EVIDENCE_ARTICLES = 6
    MIN_BODY_WORDS = 150
    UNITED_STATES = "United States"

    def initialize(source_registry:)
      @source_registry = source_registry.index_by { |source| source.fetch("slug") }
    end

    def call(cluster_id:, cluster:, articles:)
      cluster_urls = cluster.fetch("articles").pluck("canonical_url")
      members = articles.select { |article| cluster_urls.include?(article.fetch("canonical_url")) }
      raise ArgumentError, "cluster members are missing from the article corpus" unless members.length == cluster_urls.length

      evidence = select_evidence(members, cluster)
      raise ArgumentError, "cluster has no article body of at least #{MIN_BODY_WORDS} words" if evidence.empty?

      dates = members.filter_map { |article| article["published_at"] }
      publishers = members.pluck("source_slug").uniq

      {
        "event" => {
          "uri" => cluster_id,
          "title" => working_title(members, cluster),
          "event_date" => dates.min&.to_date&.iso8601,
          "location" => nil,
          "country" => nil
        },
        "coverage" => {
          "article_count" => members.length,
          "substantial_article_count" => members.count { |article| substantial?(article) },
          "publisher_count" => publishers.length,
          "single_source" => publishers.one?,
          "united_states_publishers" => publishers.count do |slug|
            @source_registry.fetch(slug).fetch("country") == UNITED_STATES
          end,
          "coverage_start" => dates.min,
          "coverage_end" => dates.max
        },
        "concepts" => [],
        "evidence" => evidence
      }
    end

    private

    def select_evidence(members, cluster)
      substantial = members.select { |article| substantial?(article) }
      source_representatives = substantial.group_by { |article| article.fetch("source_slug") }.values.map do |articles|
        articles.max_by { |article| article_order(article, cluster) }
      end
      source_representatives.sort_by { |article| article_order(article, cluster) }.reverse
        .first(MAX_EVIDENCE_ARTICLES)
        .map { |article| normalize_article(article, cluster) }
    end

    def working_title(members, cluster)
      members.max_by { |article| article_order(article, cluster) }.fetch("title")
    end

    def article_order(article, cluster)
      [ centrality(article, cluster), article["published_at"].to_s, article.fetch("canonical_url") ]
    end

    def centrality(article, cluster)
      pairs = cluster.fetch("pairwise_similarities", [])
      scores = pairs.filter_map do |pair|
        left = pair["left"] == article["title"] && pair["left_source"] == article["source_name"]
        right = pair["right"] == article["title"] && pair["right_source"] == article["source_name"]
        pair["similarity"] if left || right
      end
      return scores.sum.fdiv(scores.length) if scores.any?

      cluster.fetch("articles").one? ? 1.0 : 0.0
    end

    def substantial?(article)
      article.fetch("word_count") >= MIN_BODY_WORDS && article.fetch("body_text").present?
    end

    def normalize_article(article, cluster)
      source = @source_registry.fetch(article.fetch("source_slug"))
      {
        "uri" => article.fetch("id").to_s,
        "title" => article.fetch("title"),
        "url" => article.fetch("canonical_url"),
        "published_at" => article["published_at"],
        "source" => article.fetch("source_name"),
        "domain" => URI(article.fetch("canonical_url")).host,
        "source_country" => source.fetch("country"),
        "source_role" => source.fetch("country") == UNITED_STATES ? "united_states" : "international",
        "body" => article.fetch("body_text"),
        "body_words" => article.fetch("word_count"),
        "completeness" => completeness(article),
        "cluster_centrality" => centrality(article, cluster).round(6)
      }
    end

    def completeness(article)
      return "live_page" if article.fetch("canonical_url").include?("/live/")
      return "provisional" if article.fetch("body_text").match?(/developing story/i)

      "substantial"
    end
  end
end
