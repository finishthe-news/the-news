module EditorialRanking
  class AudiencePolicy
    AUDIENCE_CONTINENTS = [ "Europe", "North America" ].freeze
    CONTINENT_ALIASES = { "Noth America" => "North America" }.freeze

    def classify(source, event_country:)
      country = country_name(source)
      return "local" if country.present? && country.casecmp?(event_country.to_s)
      return "audience" if AUDIENCE_CONTINENTS.include?(continent_name(source))

      "excluded"
    end

    def country_name(source)
      location = source.fetch("location", {}) || {}
      localized(location.dig("country", "label")) ||
        (location["type"] == "country" ? localized(location["label"]) : nil)
    end

    def continent_name(source)
      location = source.fetch("location", {}) || {}
      continent = location.dig("country", "continent") || location["continent"]
      CONTINENT_ALIASES.fetch(localized(continent), localized(continent))
    end

    def localized(value)
      value.is_a?(Hash) ? value["eng"] || localized(value["label"]) : value
    end
  end
end
