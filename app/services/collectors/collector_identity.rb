module Collectors
  class CollectorIdentity
    class MissingContact < StandardError; end

    class << self
      def value
        contact = ENV["NEWS_COLLECTOR_CONTACT"].to_s.strip
        if Rails.env.production? && contact.blank?
          raise MissingContact, "NEWS_COLLECTOR_CONTACT is required in production"
        end

        details = [ "+https://finishthe.news" ]
        details << "mailto:#{contact}" if contact.present?
        "TheNews/#{TheNews::VERSION} (#{details.join("; ")})"
      end
    end
  end
end
