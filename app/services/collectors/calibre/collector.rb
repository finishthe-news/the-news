require "fileutils"
require "tmpdir"

module Collectors
  module Calibre
    class Collector
      ADAPTER_NAME = "calibre".freeze
      ADAPTER_VERSION = "1".freeze

      class MissingApprovedPolicy < StandardError; end
      class CollectionFailure < StandardError
        attr_reader :collection_run

        def initialize(message, collection_run:)
          @collection_run = collection_run
          super(message)
        end
      end

      def initialize(
        source:,
        manifest:,
        runner: RecipeRunner.new,
        clock: -> { Time.current },
        run_parent: Rails.root.join("tmp/calibre-runs")
      )
        @source = source
        @manifest = manifest
        @runner = runner
        @clock = clock
        @run_parent = Pathname(run_parent)
      end

      def call
        validate_source!
        policy = @source.approved_policy
        raise MissingApprovedPolicy, @source.slug unless policy

        run = @source.collection_runs.create!(
          source_policy: policy,
          adapter_name: ADAPTER_NAME,
          adapter_version: ADAPTER_VERSION,
          started_at: @clock.call
        )

        @run_parent.mkpath
        Dir.mktmpdir("#{@source.slug}-", @run_parent) do |run_root|
          bridge = @runner.call(
            manifest: @manifest,
            known_state: KnownState.new(source: @source).as_json,
            run_root:
          )
          persistence = Persister.new(
            source: @source,
            policy:,
            collection_run: run,
            run_root:,
            allowed_hosts: @manifest.discovery.article_hosts + @manifest.discovery.redirect_hosts,
            clock: @clock
          ).call(records: bridge.records, observations: bridge.observations)

          unless bridge.successful? && persistence.errors.empty?
            message = failure_message(bridge, persistence)
            raise CollectionFailure.new(message, collection_run: run)
          end

          run.update!(
            status: "succeeded",
            finished_at: @clock.call,
            documents_seen: persistence.documents_seen,
            documents_created: persistence.documents_created,
            snapshots_created: persistence.snapshots_created,
            metadata: receipt_metadata(bridge, persistence)
          )
        end
        run
      rescue => error
        failed_run = error.respond_to?(:collection_run) ? error.collection_run : run
        fail_run(failed_run, error) if failed_run&.persisted?
        raise error unless failed_run&.persisted?
        raise error if error.is_a?(CollectionFailure) || error.is_a?(MissingApprovedPolicy)

        raise CollectionFailure.new(error.message, collection_run: failed_run), cause: error
      end

      private

      def validate_source!
        raise ArgumentError, "source does not match manifest" unless @source.slug == @manifest.slug
        raise ArgumentError, "source is inactive" unless @source.active?
      end

      def failure_message(bridge, persistence)
        return "Calibre bridge outcome was #{bridge.report.fetch('outcome')}" unless bridge.successful?

        "Calibre persistence rejected #{persistence.errors.length} receipt(s)"
      end

      def receipt_metadata(bridge, persistence)
        {
          "calibre" => bridge.report.slice(
            "outcome", "elapsed_seconds", "calibre_exit_code", "counts", "instrumentation"
          ),
          "observations_created" => persistence.observations_created,
          "persistence_errors" => persistence.errors
        }
      end

      def fail_run(run, error)
        run.update_columns(
          status: "failed",
          finished_at: @clock.call,
          error_class: error.class.name,
          error_message: error.message.to_s.first(2_000),
          updated_at: @clock.call
        )
      end
    end
  end
end
