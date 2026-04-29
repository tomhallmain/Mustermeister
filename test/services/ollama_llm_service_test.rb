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

  test "available_models reads locally downloaded models from tags endpoint" do
    fake_http = Class.new do
      def open_timeout=(_value); end
      def read_timeout=(_value); end

      def request(_req)
        Struct.new(:body) do
          def is_a?(klass)
            klass == Net::HTTPSuccess
          end
        end.new('{"models":[{"name":"llama3:8b"},{"name":"deepseek-r1:14b"}]}')
      end
    end.new

    Net::HTTP.stub :new, fake_http do
      assert_equal ["deepseek-r1:14b", "llama3:8b"], OllamaLlmService.available_models
    end
  end
end
