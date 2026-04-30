require "test_helper"

class TaskInsightsChatServiceTest < ActiveSupport::TestCase
  test "rejects final step when answer is structured JSON instead of a string" do
    service = TaskInsightsChatService.new(user: users(:one), locale: :en, progress: nil)
    data = { "type" => "final", "answer" => { "project_totals" => { "A" => 1 } } }
    step = service.send(:normalize_step, data, transcript: [])
    assert_equal "invalid", step["type"]
  end

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

  test "notifies progress on each state change" do
    responses = [
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"Only final."}')
    ]
    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        @responses.shift
      end
    end.new(responses)

    syncs = []
    progress = Object.new
    progress.define_singleton_method(:sync) do |state_events:, tool_calls:|
      syncs << { event_count: state_events.size, tool_count: tool_calls.size }
    end

    OllamaLlmService.stub :new, fake_llm do
      TaskInsightsChatService.call(
        user: users(:one),
        question: "Quick",
        progress: progress
      )
    end

    assert_operator syncs.size, :>=, 2
    assert_operator syncs.last[:event_count], :>=, 2
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

  test "accepts tool_calls array shape with tool_name and tool_args" do
    responses = [
      OllamaLlmService::Result.new(response: '{"tool_calls":[{"tool_name":"status_breakdown","tool_args":{}}]}'),
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
