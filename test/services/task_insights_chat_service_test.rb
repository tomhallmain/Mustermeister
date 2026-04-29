require "test_helper"

class TaskInsightsChatServiceTest < ActiveSupport::TestCase
  test "executes tool call then returns final answer" do
    responses = [
      OllamaLlmService::Result.new(response: '{"type":"tool_call","tool":"status_breakdown","arguments":{}}'),
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"You have mostly not started tasks."}')
    ]

    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        raise "missing system prompt" if system_prompt.blank?
        @responses.shift
      end
    end.new(responses)

    OllamaLlmService.stub :new, fake_llm do
      result = TaskInsightsChatService.call(user: users(:one), question: "What patterns do you see?")
      assert_equal "You have mostly not started tasks.", result.answer
      assert_equal 1, result.tool_calls.size
      assert_equal "status_breakdown", result.tool_calls.first[:tool]
    end
  end

  test "accepts legacy tool_call shape without type field" do
    responses = [
      OllamaLlmService::Result.new(response: '{"tool":"status_breakdown","arguments":{}}'),
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"Done."}')
    ]

    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        raise "missing system prompt" if system_prompt.blank?
        @responses.shift
      end
    end.new(responses)

    OllamaLlmService.stub :new, fake_llm do
      result = TaskInsightsChatService.call(user: users(:one), question: "Breakdown?")
      assert_equal "Done.", result.answer
      assert_equal "status_breakdown", result.tool_calls.first[:tool]
    end
  end

  test "falls back when model returns empty final" do
    responses = [
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"   "}')
    ]

    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        @responses.shift
      end
    end.new(responses)

    OllamaLlmService.stub :new, fake_llm do
      result = TaskInsightsChatService.call(user: users(:one), question: "Hi", locale: :en)
      assert_includes result.answer, "rephrasing"
      assert result.state_events.any? { |e| e[:state] == "final_answer_empty" }
    end
  end
end
