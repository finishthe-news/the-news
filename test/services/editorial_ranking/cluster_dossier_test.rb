require "test_helper"

class EditorialRanking::ClusterDossierTest < ActiveSupport::TestCase
  test "builds a geographically eligible and source-diverse dossier" do
    dossier = EditorialRanking::ClusterDossier.new(client: fake_client).call(event_uri: "eng-test")

    assert_equal "Thailand", dossier.dig("event", "country")
    assert_equal 3, dossier.dig("coverage", "eligible_publishers_in_sample")
    assert_equal 1, dossier.dig("coverage", "local_publishers_in_sample")
    assert_equal 2, dossier.dig("coverage", "audience_publishers_in_sample")
    assert_equal %w[bangkokpost.com bbc.com nytimes.com], dossier.fetch("evidence").pluck("domain")
    assert_not_includes dossier.fetch("evidence").pluck("domain"), "indiatimes.com"
    assert_equal "insufficient", dossier.fetch("evidence").last.fetch("completeness")
  end

  test "renders a markdown ranking prompt without asking the model to filter publishers" do
    dossier = EditorialRanking::ClusterDossier.new(client: fake_client).call(event_uri: "eng-test")
    prompt = EditorialRanking::Prompt.render(dossier, include_bodies: false)

    assert_includes prompt, "# Scoring rubric"
    assert_includes prompt, "Do not infer consequence or geographic reach from article volume."
    assert_includes prompt, "`2` — A city, province, state, or region."
    assert_includes prompt, "`5` — Catastrophic, systemic, or historically consequential effects."
    assert_includes prompt.squish,
      "Evidence selection and exact-publisher deduplication have already been applied."
    assert_includes prompt, "[Body omitted from review: 180 words]"
    assert_not_includes prompt, "indiatimes.com"
  end

  private

  def fake_client
    Class.new do
      def event_info(_event_uri)
        {
          "title" => { "eng" => "Thailand school shooting" },
          "eventDate" => "2026-08-07",
          "location" => {
            "type" => "place",
            "label" => { "eng" => "Bangkok" },
            "country" => { "label" => { "eng" => "Thailand" } }
          },
          "totalArticleCount" => 100,
          "articleCounts" => { "eng" => 60 },
          "concepts" => [ { "label" => { "eng" => "Thailand" }, "score" => 100 } ]
        }
      end

      def event_sources(_event_uri)
        {
          "results" => [
            source_result("Bangkok Post", "bangkokpost.com", "Thailand", "Asia", 4),
            source_result("BBC", "bbc.com", "United Kingdom", "Europe", 3),
            source_result("New York Times", "nytimes.com", "United States", "North America", 2),
            source_result("India Times", "indiatimes.com", "India", "Asia", 8)
          ]
        }
      end

      def event_articles(_event_uri, sort_by:, count:, source_uris: nil)
        raise unless count == EditorialRanking::ClusterDossier::ARTICLE_SAMPLE_COUNT

        articles = [
          article("1", "Bangkok Post", "bangkokpost.com", "Thailand", "Asia", 180),
          article("2", "BBC", "bbc.com", "United Kingdom", "Europe", 200),
          article("3", "New York Times", "nytimes.com", "United States", "North America", 100),
          article("4", "India Times", "indiatimes.com", "India", "Asia", 500),
          article("5", "BBC", "bbc.com", "United Kingdom", "Europe", 350)
        ]
        results = sort_by == "cosSim" ? articles.reverse : articles
        results = results.select { |article| source_uris.include?(article.dig("source", "uri")) } if source_uris
        { "results" => results }
      end

      private

      def source_result(title, domain, country, continent, count)
        {
          "source" => source(title, domain, country, continent),
          "counts" => [ { "date" => "2026-08-07", "count" => count } ]
        }
      end

      def article(uri, title, domain, country, continent, words)
        {
          "uri" => uri,
          "title" => "Article #{uri}",
          "url" => "https://#{domain}/article-#{uri}",
          "dateTime" => "2026-08-07T00:00:00Z",
          "body" => ([ "word" ] * words).join(" "),
          "source" => source(title, domain, country, continent)
        }
      end

      def source(title, domain, country, continent)
        {
          "title" => title,
          "uri" => domain,
          "location" => {
            "type" => "place",
            "country" => {
              "label" => { "eng" => country },
              "continent" => { "label" => { "eng" => continent } }
            }
          }
        }
      end
    end.new
  end
end
