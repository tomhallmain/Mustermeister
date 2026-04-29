require "test_helper"

class OllamaLlmServiceTest < ActiveSupport::TestCase
  test "result json_attr extracts value from json response" do
    result = OllamaLlmService::Result.new(response: '{"summary":"ok","score":3}')
    assert_equal "ok", result.json_attr("summary")
    assert_equal 3, result.json_attr("score")
  end

  test "result json_attr supports fuzzy key matching" do
    result = OllamaLlmService::Result.new(response: '{"completion_ratio": 92}')
    assert_equal 92, result.json_attr("completion ratio")
  end
end
