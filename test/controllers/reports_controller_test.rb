# frozen_string_literal: true

require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  def setup
    ReportsController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    @included_project = projects(:one)
    sign_in_as(@user, skip_redirect: true)

    setup_paper_trail(@user)
  end

  def teardown
    ReportsController.class_eval do
      layout 'application'
    end

    teardown_paper_trail
  end

  def stub_llm
    Class.new do
      attr_reader :prompt_received

      def generate_response(prompt, system_prompt:)
        @prompt_received = prompt
        OllamaLlmService::Result.new(response: "AI summary")
      end
    end.new
  end

  # Regression test: ReportLlmSummaryService (unlike TaskInsightsChatService)
  # has no built-in awareness of task_insights_excluded_project_ids - it just
  # summarizes whatever ReportStatsService::Result it's handed. The fix lives
  # in ReportsController#analysis, which must build a *separate*,
  # exclusion-filtered result specifically for the AI summary rather than
  # reusing @result (which intentionally still includes every selected
  # project for the human-facing page itself).
  test "AI summary excludes task_insights_excluded_project_ids even though the report page includes those projects" do
    excluded_project = Project.create!(title: "Excluded Project", user: @user)
    excluded_project.create_task!(title: "Secret Excluded Task", user: @user)
    @included_project.create_task!(title: "Visible Included Task", user: @user)
    @user.update!(task_insights_excluded_project_ids: [excluded_project.id])

    fake_llm = stub_llm
    OllamaLlmService.stub :available_models, ["llama3"] do
      OllamaLlmService.stub :new, fake_llm do
        get reports_analysis_path, params: { ai_summary: "1", ai_locale: "en", ai_model: "llama3" }
      end
    end

    assert_response :success
    assert_not_includes fake_llm.prompt_received, "Secret Excluded Task"
    assert_not_includes fake_llm.prompt_received, "Excluded Project"
    assert_includes fake_llm.prompt_received, "Visible Included Task"
  end

  test "AI summary generation does not error when every relevant project is excluded" do
    @included_project.create_task!(title: "Only Task", user: @user)
    @user.update!(task_insights_excluded_project_ids: [@included_project.id])

    fake_llm = stub_llm
    OllamaLlmService.stub :available_models, ["llama3"] do
      OllamaLlmService.stub :new, fake_llm do
        get reports_analysis_path, params: {
          ai_summary: "1", ai_locale: "en", ai_model: "llama3", project_ids: [@included_project.id]
        }
      end
    end

    assert_response :success
    # Proves the flow reached ReportLlmSummaryService (and thus successfully
    # built a - empty but valid - ReportStatsService::Result) rather than
    # raising and falling into the rescue branch before ever calling it.
    assert fake_llm.prompt_received.present?
    assert_not_includes fake_llm.prompt_received, "Only Task"
  end

  test "regular report rendering still includes excluded projects - exclusion only affects the AI summary" do
    excluded_project = Project.create!(title: "Excluded But Visible Project", user: @user)
    excluded_project.create_task!(title: "Task In Excluded Project", user: @user)
    @user.update!(task_insights_excluded_project_ids: [excluded_project.id])

    get reports_analysis_path
    assert_response :success
    assert_match "Excluded But Visible Project", response.body
  end
end
