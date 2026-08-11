module Collectors
  module Calibre
    class SoakReport
      DEFAULT_HOURS = 24

      def initialize(hours: DEFAULT_HOURS)
        raise ArgumentError, "hours must be positive" unless hours.positive?

        @hours = hours
      end

      def call(ending_slot: Time.current.beginning_of_hour)
        expected_slots = @hours.times.map do |offset|
          ending_slot.in_time_zone.beginning_of_hour - offset.hours
        end.reverse
        cycles = NewsCollectionCycle.where(slot_at: expected_slots).includes(
          news_collection_slots: [ :source, :collection_run ]
        ).index_by(&:slot_at)
        issues = []

        expected_slots.each do |slot_at|
          cycle = cycles[slot_at]
          unless cycle
            issues << issue("missing_cycle", slot_at: slot_at.iso8601)
            next
          end
          issues.concat(cycle_issues(cycle))
        end
        issues.concat(overlap_issues(expected_slots))
        issues.concat(duplicate_document_issues)

        {
          "schema_version" => "calibre-soak-report/v1",
          "hours" => @hours,
          "starts_at" => expected_slots.first.iso8601,
          "ends_at" => expected_slots.last.iso8601,
          "cycles_found" => cycles.length,
          "passed" => issues.empty?,
          "issues" => issues
        }
      end

      private

      def cycle_issues(cycle)
        issues = []
        unless cycle.status_completed?
          issues << issue("cycle_not_completed", slot_at: cycle.slot_at.iso8601, status: cycle.status)
        end

        slots_by_slug = cycle.news_collection_slots.index_by { |slot| slot.source.slug }
        actual_slugs = slots_by_slug.keys.sort
        if actual_slugs != cycle.expected_source_slugs
          issues << issue(
            "source_receipt_mismatch",
            slot_at: cycle.slot_at.iso8601,
            expected: cycle.expected_source_slugs,
            actual: actual_slugs
          )
        end

        slots_by_slug.each_value do |slot|
          issues.concat(slot_issues(slot))
        end
        issues
      end

      def slot_issues(slot)
        return [ issue("source_slot_not_terminal", slot_id: slot.id, status: slot.status) ] if slot.status_claimed?
        return [] if slot.status_failed? && slot.collection_run.nil?

        run = slot.collection_run
        if run.nil? || run.source_id != slot.source_id || run.status != slot.status
          [ issue(
            "collection_run_mismatch",
            slot_id: slot.id,
            slot_status: slot.status,
            run_status: run&.status
          ) ]
        else
          []
        end
      end

      def overlap_issues(expected_slots)
        NewsCollectionSlot
          .where(slot_at: expected_slots)
          .where.not(finished_at: nil)
          .order(:source_id, :claimed_at)
          .group_by(&:source_id)
          .flat_map do |source_id, slots|
            slots.each_cons(2).filter_map do |first, second|
              next unless first.finished_at > second.claimed_at

              issue(
                "overlapping_source_runs",
                source_id:,
                first_slot_id: first.id,
                second_slot_id: second.id
              )
            end
          end
      end

      def duplicate_document_issues
        SourceDocument
          .group(:source_id, :canonical_url)
          .having("COUNT(*) > 1")
          .count
          .map do |(source_id, canonical_url), count|
            issue("duplicate_canonical_document", source_id:, canonical_url:, count:)
          end
      end

      def issue(code, details = {})
        { "code" => code }.merge(details.stringify_keys)
      end
    end
  end
end
