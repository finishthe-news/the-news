require "digest"
require "json"

class CanonicalJson
  class << self
    def dump(value)
      JSON.generate(normalize(value))
    end

    def sha256(value)
      Digest::SHA256.hexdigest(dump(value))
    end

    private

    def normalize(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [ key, normalize(value.fetch(key)) ] }
      when Array
        value.map { |item| normalize(item) }
      else
        value
      end
    end
  end
end
