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

  test "accepts top-level tool_name with parameters alias" do
    responses = [
      OllamaLlmService::Result.new(response: '{"tool_name":"status_breakdown","parameters":{}}'),
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

  test "maps wrapped get_tasks function to local search_tasks tool" do
    responses = [
      OllamaLlmService::Result.new(
        response: '{"tool_calls":[{"function":"get_tasks","args":{"project":"Code Generation","since_date":"2024-05-20"}}]}'
      ),
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
      result = TaskInsightsChatService.call(user: users(:one), question: "Find trends")
      assert_equal "Done.", result.answer
      assert_equal "search_tasks", result.tool_calls.first[:tool]
      assert_equal "Code Generation", result.tool_calls.first[:arguments]["keyword"]
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

  test "treats model error payload as terminal without repair" do
    responses = [
      OllamaLlmService::Result.new(response: '{"error":"No items found"}')
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
      assert_equal "Model error: No items found", result.answer
      assert result.state_events.any? { |e| e[:state] == "model_error_payload" }
      assert result.state_events.none? { |e| e[:state] == "attempting_json_repair" }
    end
  end

  test "open_tasks_by_priorities returns grouped compact payload" do
    service = TaskInsightsChatService.new(user: users(:one), locale: :en, progress: nil)
    payload = service.send(:open_tasks_by_priorities, { "priorities" => %w[medium high], "limit" => 50 })

    assert payload[:priorities].is_a?(Hash)
    assert payload[:returned_count].is_a?(Integer)
    assert payload[:total_matching_count].is_a?(Integer)
    assert payload[:limit].is_a?(Integer)

    any_task = payload[:priorities].values
      .flat_map { |p| p[:statuses].values }
      .flat_map { |s| s[:projects].values }
      .flatten
      .first

    if any_task
      assert any_task.key?(:updated_date)
      assert_not any_task.key?(:updated_at)
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, any_task[:updated_date])
    end
  end
end
