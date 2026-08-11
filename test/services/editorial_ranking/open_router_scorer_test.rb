require "test_helper"

class EditorialRanking::OpenRouterScorerTest < ActiveSupport::TestCase
  FakeTransport = Struct.new(:response, :requests) do
    def post(uri, headers:, body:)
      requests << { uri:, headers:, body: JSON.parse(body) }
      response
    end
  end

  test "requests and validates a strict editorial score" do
    response = EditorialRanking::OpenRouterScorer::Response.new(
      status: 200,
      body: JSON.generate(
        "id" => "generation-1",
        "model" => "openai/gpt-5.4-mini",
        "provider" => "OpenAI",
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50 },
        "choices" => [
          {
            "message" => {
              "content" => JSON.generate(
                "primary_section" => "world",
                "scores" => {
                  "consequence" => 3,
                  "audience_relevance" => 2,
                  "geographic_reach" => 2,
                  "public_interest" => 4,
                  "novelty" => 4
                },
                "confidence" => 0.8,
                "reason" => "A serious but geographically limited event."
              )
            }
          }
        ]
      )
    )
    transport = FakeTransport.new(response, [])
    scorer = EditorialRanking::OpenRouterScorer.new(
      api_key: "secret",
      model: "openai/gpt-5.4-mini",
      transport:
    )

    result = scorer.call("# Event\n\nTest")

    assert_equal "world", result.score.fetch("primary_section")
    assert_equal "OpenAI", result.provider
    assert_equal 1, transport.requests.size
    request = transport.requests.fetch(0)
    assert_equal "Bearer secret", request.dig(:headers, "Authorization")
    assert_equal "json_schema", request.dig(:body, "response_format", "type")
    assert request.dig(:body, "provider", "require_parameters")
  end

  test "pins an explicitly reviewed provider route without fallback" do
    response = EditorialRanking::OpenRouterScorer::Response.new(
      status: 200,
      body: JSON.generate(
        "choices" => [
          {
            "message" => {
              "content" => JSON.generate(
                "primary_section" => "world",
                "scores" => {
                  "consequence" => 3,
                  "audience_relevance" => 2,
                  "geographic_reach" => 2,
                  "public_interest" => 4,
                  "novelty" => 4
                },
                "confidence" => 0.8,
                "reason" => "A serious but geographically limited event."
              )
            }
          }
        ]
      )
    )
    transport = FakeTransport.new(response, [])
    scorer = EditorialRanking::OpenRouterScorer.new(
      api_key: "secret",
      model: "deepseek/deepseek-v3.2",
      provider_route: "siliconflow/fp8",
      reasoning: { enabled: false },
      transport:
    )

    scorer.call("test")

    policy = transport.requests.fetch(0).dig(:body, "provider")
    assert_equal [ "siliconflow/fp8" ], policy.fetch("only")
    assert_equal [ "siliconflow/fp8" ], policy.fetch("order")
    assert_equal false, policy.fetch("allow_fallbacks")
    assert_equal "deny", policy.fetch("data_collection")
    assert_equal true, policy.fetch("zdr")
    assert_equal({ "enabled" => false }, transport.requests.fetch(0).dig(:body, "reasoning"))
  end

  test "rejects an out of range score even if the provider returns JSON" do
    response = EditorialRanking::OpenRouterScorer::Response.new(
      status: 200,
      body: JSON.generate(
        "choices" => [
          {
            "message" => {
              "content" => JSON.generate(
                "primary_section" => "world",
                "scores" => {
                  "consequence" => 9,
                  "audience_relevance" => 2,
                  "geographic_reach" => 2,
                  "public_interest" => 4,
                  "novelty" => 4
                },
                "confidence" => 0.8,
                "reason" => "Invalid."
              )
            }
          }
        ]
      )
    )
    scorer = EditorialRanking::OpenRouterScorer.new(
      api_key: "secret",
      model: "openai/gpt-5.4-mini",
      transport: FakeTransport.new(response, [])
    )

    assert_raises(EditorialRanking::OpenRouterScorer::Error) do
      scorer.call("test")
    end
  end
end
