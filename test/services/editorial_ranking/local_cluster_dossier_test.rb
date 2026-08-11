require "test_helper"

class EditorialRanking::LocalClusterDossierTest < ActiveSupport::TestCase
  test "selects one substantial representative per publisher up to six" do
    dossier = builder.call(cluster_id: "cluster-1", cluster:, articles:)

    assert_equal "Central report", dossier.dig("event", "title")
    assert_equal 4, dossier.dig("coverage", "article_count")
    assert_equal 3, dossier.dig("coverage", "substantial_article_count")
    assert_equal 3, dossier.dig("coverage", "publisher_count")
    assert_equal false, dossier.dig("coverage", "single_source")
    assert_equal 1, dossier.dig("coverage", "united_states_publishers")
    assert_equal %w[bbc npr], dossier.fetch("evidence").pluck("source").sort
    assert_equal %w[international united_states], dossier.fetch("evidence").pluck("source_role").sort
  end

  test "allows a substantial singleton dossier" do
    singleton = article(id: 9, slug: "npr", source: "npr", title: "Exclusive", words: 250)
    cluster = { "articles" => [ { "canonical_url" => singleton.fetch("canonical_url") } ] }
    dossier = builder.call(cluster_id: "singleton-9", cluster:, articles: [ singleton ])

    assert_equal true, dossier.dig("coverage", "single_source")
    assert_equal 1, dossier.fetch("evidence").length
    assert_equal "Exclusive", dossier.dig("event", "title")
  end

  test "rejects a cluster without a substantial body" do
    short = article(id: 10, slug: "npr", source: "npr", title: "Video", words: 20)
    cluster = { "articles" => [ { "canonical_url" => short.fetch("canonical_url") } ] }

    assert_raises(ArgumentError) do
      builder.call(cluster_id: "singleton-10", cluster:, articles: [ short ])
    end
  end

  private

  def builder
    EditorialRanking::LocalClusterDossier.new(
      source_registry: [
        { "slug" => "npr", "country" => "United States" },
        { "slug" => "bbc", "country" => "United Kingdom" },
        { "slug" => "dw", "country" => "Germany" }
      ]
    )
  end

  def cluster
    {
      "articles" => articles.map { |article| { "canonical_url" => article.fetch("canonical_url") } },
      "pairwise_similarities" => [
        {
          "left" => "Central report", "left_source" => "bbc",
          "right" => "US report", "right_source" => "npr", "similarity" => 0.97
        },
        {
          "left" => "Central report", "left_source" => "bbc",
          "right" => "Second BBC report", "right_source" => "bbc", "similarity" => 0.92
        },
        {
          "left" => "US report", "left_source" => "npr",
          "right" => "Second BBC report", "right_source" => "bbc", "similarity" => 0.89
        }
      ]
    }
  end

  def articles
    [
      article(id: 1, slug: "bbc", source: "bbc", title: "Central report", words: 300),
      article(id: 2, slug: "npr", source: "npr", title: "US report", words: 260),
      article(id: 3, slug: "bbc", source: "bbc", title: "Second BBC report", words: 220),
      article(id: 4, slug: "dw", source: "dw", title: "Short report", words: 40)
    ]
  end

  def article(id:, slug:, source:, title:, words:)
    {
      "id" => id,
      "source_slug" => slug,
      "source_name" => source,
      "title" => title,
      "canonical_url" => "https://#{source}.example/#{id}",
      "published_at" => "2026-08-10T0#{id}:00:00Z",
      "body_text" => ([ "word" ] * words).join(" "),
      "word_count" => words
    }
  end
end
