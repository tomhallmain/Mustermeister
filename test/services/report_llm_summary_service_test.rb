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
    assert_includes fake_llm.prompt_received, "total_tasks: 10"
    assert_includes fake_llm.system_prompt_received, "summarizes project analytics"
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
