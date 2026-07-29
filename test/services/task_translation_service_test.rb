require "test_helper"

class TaskTranslationServiceTest < ActiveSupport::TestCase
  def setup
    @task = tasks(:one)
  end

  test "returns the translated title and description" do
    fake_llm = Class.new do
      attr_reader :prompt_received, :system_prompt_received

      def generate_response(prompt, system_prompt:)
        @prompt_received = prompt
        @system_prompt_received = system_prompt
        OllamaLlmService::Result.new(response: '{"title": "Titulo traducido", "description": "Descripcion traducida"}')
      end
    end.new

    result = nil
    OllamaLlmService.stub :new, fake_llm do
      result = TaskTranslationService.call(task: @task, target_language: "Spanish", model_name: "llama3")
    end

    assert_equal({ title: "Titulo traducido", description: "Descripcion traducida" }, result)
    assert_includes fake_llm.prompt_received, "Spanish"
    assert_includes fake_llm.prompt_received, @task.title
    assert_includes fake_llm.system_prompt_received, "translate"
  end

  test "handles a response wrapped in a markdown code fence" do
    fake_llm = Class.new do
      def generate_response(_prompt, system_prompt:)
        OllamaLlmService::Result.new(response: "```json\n{\"title\": \"Titre\", \"description\": \"\"}\n```")
      end
    end.new

    result = nil
    OllamaLlmService.stub :new, fake_llm do
      result = TaskTranslationService.call(task: @task, target_language: "French", model_name: "llama3")
    end

    assert_equal({ title: "Titre", description: "" }, result)
  end

  test "raises TranslationError when no target language is given" do
    assert_raises(TaskTranslationService::TranslationError) do
      TaskTranslationService.call(task: @task, target_language: "", model_name: "llama3")
    end
  end

  test "raises TranslationError when no model is given" do
    assert_raises(TaskTranslationService::TranslationError) do
      TaskTranslationService.call(task: @task, target_language: "Spanish", model_name: "")
    end
  end

  test "raises TranslationError when the LLM response has no usable title" do
    fake_llm = Class.new do
      def generate_response(_prompt, system_prompt:)
        OllamaLlmService::Result.new(response: '{"description": "Something"}')
      end
    end.new

    OllamaLlmService.stub :new, fake_llm do
      assert_raises(TaskTranslationService::TranslationError) do
        TaskTranslationService.call(task: @task, target_language: "Spanish", model_name: "llama3")
      end
    end
  end

  test "wraps an OllamaLlmService::ResponseError as a TranslationError" do
    fake_llm = Class.new do
      def generate_response(_prompt, system_prompt:)
        raise OllamaLlmService::ResponseError, "boom"
      end
    end.new

    OllamaLlmService.stub :new, fake_llm do
      error = assert_raises(TaskTranslationService::TranslationError) do
        TaskTranslationService.call(task: @task, target_language: "Spanish", model_name: "llama3")
      end
      assert_equal "boom", error.message
    end
  end
end
