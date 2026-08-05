require "net/http"

module Collectors
  class HttpClient
    Response = Data.define(:status, :body, :headers, :final_url)

    def initialize(open_timeout: 10, read_timeout: 30, redirect_limit: 5)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @redirect_limit = redirect_limit
    end

    def get(uri, headers: {})
      request(uri, headers:, redirects_remaining: @redirect_limit)
    end

    private

    def request(uri, headers:, redirects_remaining:)
      raise ArgumentError, "redirect limit exceeded" if redirects_remaining.negative?

      request = Net::HTTP::Get.new(uri)
      headers.each { |name, value| request[name] = value }

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) { |http| http.request(request) }

      if response.is_a?(Net::HTTPRedirection)
        redirect_uri = URI.join(uri.to_s, response.fetch("location"))
        return request(
          redirect_uri,
          headers:,
          redirects_remaining: redirects_remaining - 1
        )
      end

      Response.new(
        status: response.code.to_i,
        body: response.body.to_s,
        headers: response.each_header.to_h,
        final_url: uri.to_s
      )
    end
  end
end
