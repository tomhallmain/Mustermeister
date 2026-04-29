require "test_helper"

class ReportLlmSummaryServiceTest < ActiveSupport::TestCase
  test "calls ollama service and returns summary text" do
    result = sample_result
    fake_llm = Class.new do
      attr_reader :prompt_received, :system_prompt_received

      def generate_response(prompt, system_prompt:)
        @prompt_received = prompt
        @system_prompt_received = system_prompt
        OllamaLlmService::Result.new(response: "AI summary")
      end
    end.new

    OllamaLlmService.stub :new, fake_llm do
      summary = ReportLlmSummaryService.call(result: result, locale: :en, model_name: "llama3")
      assert_equal "AI summary", summary
    end
    assert_includes fake_llm.prompt_received, "respond in English only"
    assert_includes fake_llm.prompt_received, "total_tasks: 10"
    assert_includes fake_llm.prompt_received, "Kanban snapshot"
    assert_includes fake_llm.prompt_received, "Highest-risk tasks"
    assert_includes fake_llm.system_prompt_received, "summarizes project analytics"
  end

  test "uses localized prompt copy for selected locale" do
    result = sample_result
    fake_llm = Class.new do
      attr_reader :prompt_received

      def generate_response(prompt, system_prompt:)
        @prompt_received = prompt
        OllamaLlmService::Result.new(response: "Zusammenfassung")
      end
    end.new

    OllamaLlmService.stub :new, fake_llm do
      ReportLlmSummaryService.call(result: result, locale: :de, model_name: "llama3")
    end

    assert_includes fake_llm.prompt_received, "Bitte antworte ausschliesslich auf Deutsch."
    assert_includes fake_llm.prompt_received, "Gesamtbild:"
    assert_includes fake_llm.prompt_received, "Beispiele je Gruppe"
    assert_includes fake_llm.prompt_received, "Anforderungen:"
  end

  private

  def sample_result
    summary = ReportStatsService::Summary.new(
      total_tasks: 10,
      completed_count: 6,
      incomplete_count: 4,
      completion_ratio: 60.0,
      status_breakdown: { "In Progress" => 4, "Complete" => 6 }
    )
    project = projects(:one)
    breakdown = ReportStatsService::ProjectBreakdown.new(
      project: project,
      total_tasks: 10,
      completed_count: 6,
      incomplete_count: 4,
      completion_ratio: 60.0,
      status_breakdown: { "In Progress" => 4, "Complete" => 6 }
    )
    ReportStatsService::Result.new(
      summary: summary,
      projects_summary: nil,
      projects_breakdown: [breakdown],
      project_ids: [project.id]
    )
  end
end
