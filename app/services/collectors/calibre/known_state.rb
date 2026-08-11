module Collectors
  module Calibre
    class KnownState
      SCHEMA_VERSION = "calibre-known-state/v1".freeze

      def initialize(source:)
        @source = source
      end

      def as_json(*)
        {
          "schema_version" => SCHEMA_VERSION,
          "source_slug" => @source.slug,
          "documents" => @source.source_documents.order(:canonical_url).pluck(
            :canonical_url,
            :discovery_updated_at
          ).map do |canonical_url, discovery_updated_at|
            {
              "canonical_url" => canonical_url,
              "source_updated_at" => discovery_updated_at&.iso8601
            }
          end
        }
      end
    end
  end
end
