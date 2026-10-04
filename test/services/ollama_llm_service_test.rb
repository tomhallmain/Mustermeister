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

  # Stands in for Net::HTTP, answering each request with the next of
  # `responses` (a JSON body string, or nil for a failed request), and counting
  # how many requests were made.
  def fake_tags_http(*responses)
    Class.new do
      attr_reader :requests

      define_method(:initialize) { @responses = responses.dup; @requests = 0 }
      def open_timeout=(_value); end
      def read_timeout=(_value); end

      def request(_req)
        @requests += 1
        body = @responses.shift
        Struct.new(:body, :success) do
          def is_a?(klass)
            success && klass == Net::HTTPSuccess
          end
        end.new(body, !body.nil?)
      end
    end.new
  end

  # The test environment's cache is a :null_store, which never caches.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  test "available_models serves a repeat call from the cache" do
    http = fake_tags_http('{"models":[{"name":"llama3:8b"}]}')

    with_memory_cache do
      Net::HTTP.stub :new, http do
        assert_equal ["llama3:8b"], OllamaLlmService.available_models
        assert_equal ["llama3:8b"], OllamaLlmService.available_models
      end
    end

    assert_equal 1, http.requests
  end

  test "available_models does not cache an empty result from a failed request" do
    http = fake_tags_http(nil, '{"models":[{"name":"llama3:8b"}]}')

    with_memory_cache do
      Net::HTTP.stub :new, http do
        assert_equal [], OllamaLlmService.available_models
        assert_equal ["llama3:8b"], OllamaLlmService.available_models
      end
    end

    assert_equal 2, http.requests
  end

  test "available_models with fresh: true skips the cache and refreshes it" do
    http = fake_tags_http('{"models":[{"name":"llama3:8b"}]}', '{"models":[{"name":"mistral:latest"}]}')

    with_memory_cache do
      Net::HTTP.stub :new, http do
        assert_equal ["llama3:8b"], OllamaLlmService.available_models
        assert_equal ["mistral:latest"], OllamaLlmService.available_models(fresh: true)
        assert_equal ["mistral:latest"], OllamaLlmService.available_models
      end
    end

    assert_equal 2, http.requests
  end
end
