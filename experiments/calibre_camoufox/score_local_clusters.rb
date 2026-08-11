#!/usr/bin/env ruby
require "fileutils"
require "json"
require "optparse"
require "time"

require_relative "../../config/environment"

options = {
  dataset: Rails.root.join("tmp/clustering-datasets/clustering-48h-20260810T132450Z/articles.jsonl"),
  clusters: Rails.root.join("tmp/clustering-experiments/20260810T134045Z/result.json"),
  sources: Rails.root.join("experiments/calibre_camoufox/sources.json"),
  output_root: Rails.root.join("tmp/scoring-experiments"),
  model: ENV.fetch("MODEL", EditorialRanking::OpenRouterScorer::DEFAULT_MODEL),
  provider_route: ENV.fetch("PROVIDER_ROUTE", EditorialRanking::OpenRouterScorer::DEFAULT_PROVIDER_ROUTE),
  cases: ENV.fetch("SCORING_CASES", "").split("\n").reject(&:blank?)
}

OptionParser.new do |parser|
  parser.on("--case CASE", "cluster:NUMBER or singleton:CANONICAL_URL") { |value| options[:cases] << value }
  parser.on("--model MODEL") { |value| options[:model] = value }
end.parse!
raise ArgumentError, "at least one --case is required" if options[:cases].empty?

articles = options[:dataset].each_line.map { |line| JSON.parse(line) }
articles_by_url = articles.index_by { |article| article.fetch("canonical_url") }
result = JSON.parse(options[:clusters].read)
strict_run = result.fetch("runs").find { |run| run.fetch("distance_threshold") == 0.145 }
source_registry = JSON.parse(options[:sources].read)
builder = EditorialRanking::LocalClusterDossier.new(source_registry:)
scorer = EditorialRanking::OpenRouterScorer.new(
  api_key: ENV.fetch("OPENROUTER_API_KEY"),
  model: options[:model],
  provider_route: options[:provider_route],
  reasoning: ENV["ENABLE_REASONING"] == "1" ? nil : EditorialRanking::OpenRouterScorer::DEFAULT_REASONING
)
run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
run_root = options[:output_root].join(run_id)
FileUtils.mkdir_p(run_root)
summary = {
  "run_id" => run_id,
  "model_requested" => options[:model],
  "provider_route_requested" => options[:provider_route],
  "cases" => []
}

options[:cases].each_with_index do |specification, index|
  type, identifier = specification.split(":", 2)
  cluster, cluster_id = case type
  when "cluster"
    cluster_number = Integer(identifier, 10)
    [ strict_run.fetch("clusters").fetch(cluster_number - 1), "cluster-#{cluster_number}" ]
  when "singleton"
    article = articles_by_url.fetch(identifier)
    clustered_urls = strict_run.fetch("clusters").flat_map { |item| item.fetch("articles").pluck("canonical_url") }
    raise ArgumentError, "#{identifier} is not a singleton" if clustered_urls.include?(identifier)

    [ { "articles" => [ { "canonical_url" => article.fetch("canonical_url") } ] }, "singleton-#{article.fetch('id')}" ]
  else
    raise ArgumentError, "unknown case type: #{type}"
  end

  dossier = builder.call(cluster_id:, cluster:, articles:)
  prompt = EditorialRanking::Prompt.render(dossier)
  score = scorer.call(prompt)
  case_root = run_root.join(format("%02d-%s", index + 1, cluster_id))
  FileUtils.mkdir_p(case_root)
  case_root.join("dossier.json").write(JSON.pretty_generate(dossier) + "\n")
  case_root.join("prompt.md").write(prompt)
  case_root.join("score.json").write(JSON.pretty_generate(
    "model" => score.model,
    "provider" => score.provider,
    "usage" => score.usage,
    "generation_id" => score.generation_id,
    "score" => score.score
  ) + "\n")
  summary["cases"] << {
    "case" => specification,
    "cluster_id" => cluster_id,
    "title" => dossier.dig("event", "title"),
    "articles" => dossier.dig("coverage", "article_count"),
    "publishers" => dossier.dig("coverage", "publisher_count"),
    "evidence_articles" => dossier.fetch("evidence").length,
    "prompt_characters" => prompt.length,
    "model" => score.model,
    "provider" => score.provider,
    "usage" => score.usage,
    "score" => score.score,
    "artifact_directory" => case_root.to_s
  }
end

run_root.join("summary.json").write(JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate(summary)
