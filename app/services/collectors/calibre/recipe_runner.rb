require "fileutils"
require "json"
require "open3"
require "pathname"
require "timeout"

module Collectors
  module Calibre
    class RecipeRunner
      BRIDGE_SCHEMA_VERSION = "calibre-run-report/v1".freeze
      MAX_RECEIPT_BYTES = 25.megabytes

      ProcessResult = Data.define(:stdout, :stderr, :exit_status)
      Result = Data.define(:records, :observations, :report, :process_result) do
        def successful?
          process_result.exit_status.zero? && %w[succeeded no_changes].include?(report.fetch("outcome"))
        end
      end

      class ExecutionError < StandardError; end

      def initialize(
        calibre_bin: ENV.fetch("CALIBRE_BIN", "/opt/calibre/ebook-convert"),
        python_bin: ENV.fetch("PYTHON_BIN", "python3"),
        bridge_path: Rails.root.join("lib/calibre_bridge/runner.py"),
        process_runner: nil
      )
        @calibre_bin = Pathname(calibre_bin)
        @python_bin = python_bin
        @bridge_path = Pathname(bridge_path)
        @process_runner = process_runner || method(:execute)
      end

      def call(manifest:, known_state:, run_root:)
        root = Pathname(run_root).expand_path
        root.mkpath
        known_state_path = root.join("known-state.json")
        known_state_path.write(JSON.pretty_generate(known_state) + "\n")

        command = command_for(manifest:, root:, known_state_path:)
        process_result = @process_runner.call(
          command:,
          timeout: manifest.limits.timeout_seconds + 60
        )
        report = read_json(root.join("run-report.json"))
        validate_report!(report, manifest)

        Result.new(
          records: read_jsonl(root.join("articles.jsonl")),
          observations: read_jsonl(root.join("discovery-decisions.jsonl")),
          report:,
          process_result:
        )
      rescue Errno::ENOENT, JSON::ParserError => error
        raise ExecutionError, "invalid Calibre bridge receipt: #{error.message}"
      end

      private

      def command_for(manifest:, root:, known_state_path:)
        command = [
          @python_bin,
          @bridge_path.to_s,
          *recipe_arguments(manifest),
          "--known-state", known_state_path.to_s,
          "--output-dir", root.join("output").to_s,
          "--run-dir", root.to_s,
          "--calibre-bin", @calibre_bin.to_s,
          "--timeout", manifest.limits.timeout_seconds.to_s,
          "--article-cap", manifest.limits.article_cap.to_s,
          "--concurrency-cap", manifest.limits.max_concurrency.to_s,
          "--requests-per-minute", manifest.limits.requests_per_minute.to_s
        ]
        command << "--trust-update-markers" if manifest.discovery.update_mode == "trusted_marker"
        manifest.discovery.feeds.each do |feed|
          command.concat([ "--feed", feed.fetch("url") ])
        end
        manifest.discovery.article_hosts.each do |host|
          command.concat([ "--article-host", host ])
        end
        manifest.discovery.redirect_hosts.each do |host|
          command.concat([ "--redirect-host", host ])
        end
        command
      end

      def recipe_arguments(manifest)
        case manifest.recipe.type
        when "builtin"
          [ "--builtin-recipe", manifest.recipe.id ]
        when "generic"
          [ "--source-name", manifest.name ]
        when "project"
          [ "--recipe", manifest.recipe.resolved_path ]
        else
          raise ExecutionError, "unsupported recipe type: #{manifest.recipe.type}"
        end
      end

      def read_json(path)
        ensure_receipt_size!(path)
        JSON.parse(path.read)
      end

      def read_jsonl(path)
        ensure_receipt_size!(path)
        path.each_line.filter_map do |line|
          JSON.parse(line) if line.present?
        end
      end

      def ensure_receipt_size!(path)
        raise ExecutionError, "Calibre bridge receipt is too large: #{path.basename}" if path.size > MAX_RECEIPT_BYTES
      end

      def validate_report!(report, manifest)
        unless report["schema_version"] == BRIDGE_SCHEMA_VERSION && report["source_slug"] == manifest.slug
          raise ExecutionError, "Calibre bridge report identity does not match #{manifest.slug}"
        end
        unless %w[succeeded no_changes failed].include?(report["outcome"])
          raise ExecutionError, "Calibre bridge report has an invalid outcome"
        end
      end

      def execute(command:, timeout:)
        stdout_text = stderr_text = nil
        status = nil
        Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, wait_thread|
          stdin.close
          stdout_reader = Thread.new { stdout.read }
          stderr_reader = Thread.new { stderr.read }
          begin
            status = Timeout.timeout(timeout) { wait_thread.value }
          rescue Timeout::Error
            terminate_process_group(wait_thread.pid)
            raise ExecutionError, "Calibre bridge exceeded #{timeout} seconds"
          ensure
            stdout_text = stdout_reader.value
            stderr_text = stderr_reader.value
          end
        end
        ProcessResult.new(stdout: stdout_text, stderr: stderr_text, exit_status: status.exitstatus)
      end

      def terminate_process_group(pid)
        Process.kill("TERM", -pid)
        Timeout.timeout(5) { Process.wait(pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        Process.kill("KILL", -pid)
      end
    end
  end
end
