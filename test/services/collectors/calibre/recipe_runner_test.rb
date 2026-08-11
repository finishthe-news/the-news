require "test_helper"
require "tmpdir"

class Collectors::Calibre::RecipeRunnerTest < ActiveSupport::TestCase
  setup do
    @run_root = Pathname(Dir.mktmpdir("recipe-runner-test"))
  end

  teardown do
    FileUtils.remove_entry(@run_root)
  end

  test "passes the complete manifest boundary and reads fixed receipt paths" do
    captured = nil
    process_runner = lambda do |command:, timeout:|
      captured = { command:, timeout: }
      write_receipts(outcome: "no_changes")
      process_result(exit_status: 0)
    end
    runner = Collectors::Calibre::RecipeRunner.new(
      calibre_bin: "/opt/calibre/ebook-convert",
      python_bin: "python-test",
      bridge_path: "/app/runner.py",
      process_runner:
    )

    result = runner.call(
      manifest: manifest,
      known_state: known_state,
      run_root: @run_root
    )

    assert result.successful?
    assert_empty result.records
    assert_empty result.observations
    assert_equal 660, captured.fetch(:timeout)
    assert_includes captured.fetch(:command), "--builtin-recipe"
    assert_includes captured.fetch(:command), "chr_mon.recipe"
    assert_includes captured.fetch(:command), "--requests-per-minute"
    assert_includes captured.fetch(:command), "6"
    assert_includes captured.fetch(:command), "https://example.test/feed.xml"
    assert_includes captured.fetch(:command), "--article-host"
    assert_includes captured.fetch(:command), "example.test"
    assert_equal known_state, JSON.parse(@run_root.join("known-state.json").read)
  end

  test "returns a failed bridge result for the collector to receipt" do
    process_runner = lambda do |command:, timeout:|
      write_receipts(outcome: "failed", exit_code: 1)
      process_result(exit_status: 1)
    end
    runner = Collectors::Calibre::RecipeRunner.new(process_runner:)

    result = runner.call(manifest:, known_state:, run_root: @run_root)

    assert_not result.successful?
    assert_equal "failed", result.report.fetch("outcome")
  end

  test "rejects a report for another source" do
    process_runner = lambda do |command:, timeout:|
      write_receipts(outcome: "succeeded", source_slug: "other")
      process_result(exit_status: 0)
    end
    runner = Collectors::Calibre::RecipeRunner.new(process_runner:)

    error = assert_raises(Collectors::Calibre::RecipeRunner::ExecutionError) do
      runner.call(manifest:, known_state:, run_root: @run_root)
    end

    assert_includes error.message, "does not match"
  end

  private

  def manifest
    registry = Collectors::Calibre::SourceRegistry
    registry::Manifest.new(
      version: 1,
      slug: "example-news",
      name: "Example News",
      owner_name: "Example Publisher",
      source_type: "public_reporting",
      canonical_url: "https://example.test/",
      recipe: registry::Recipe.new(type: "builtin", id: "chr_mon.recipe", path: nil, resolved_path: nil),
      discovery: registry::Discovery.new(
        feeds: [ { "url" => "https://example.test/feed.xml" } ],
        article_hosts: [ "example.test" ],
        redirect_hosts: [],
        update_mode: "unseen_only",
        update_field: nil
      ),
      limits: registry::Limits.new(
        article_cap: 10,
        timeout_seconds: 600,
        requests_per_minute: 6,
        max_concurrency: 1
      ),
      policy_proposal: nil,
      manifest_path: "/app/example.yml"
    )
  end

  def known_state
    {
      "schema_version" => "calibre-known-state/v1",
      "source_slug" => "example-news",
      "documents" => []
    }
  end

  def write_receipts(outcome:, exit_code: 0, source_slug: "example-news")
    @run_root.join("articles.jsonl").write("")
    @run_root.join("discovery-decisions.jsonl").write("")
    @run_root.join("run-report.json").write(JSON.generate(
      "schema_version" => "calibre-run-report/v1",
      "source_slug" => source_slug,
      "outcome" => outcome,
      "exit_code" => exit_code,
      "calibre_exit_code" => exit_code,
      "elapsed_seconds" => 0.1,
      "counts" => { "discovered" => 0, "eligible" => 0, "skipped" => 0, "normalized" => 0 },
      "instrumentation" => {}
    ))
  end

  def process_result(exit_status:)
    Collectors::Calibre::RecipeRunner::ProcessResult.new(
      stdout: "",
      stderr: "",
      exit_status:
    )
  end
end
