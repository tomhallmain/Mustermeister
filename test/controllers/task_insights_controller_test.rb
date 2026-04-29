require "test_helper"

class TaskInsightsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    sign_in_as(@user, skip_redirect: true)
  end

  test "should get task insights page" do
    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      get task_insights_path
      assert_response :success
      assert_select "h1", text: /Task Insights/i
    end
  end

  test "should ask question and render answer" do
    fake_result = TaskInsightsChatService::Result.new(
      answer: "Pattern detected in high-priority tasks.",
      tool_calls: [{ tool: "high_priority_open_tasks", arguments: { "limit" => 5 } }]
    )

    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      TaskInsightsChatService.stub :call, fake_result do
        get task_insights_path, params: {
          ask: "1",
          ai_locale: "en",
          ai_model: "deepseek-r1:14b",
          question: "What are risky patterns?"
        }
      end
    end

    assert_response :success
    assert_match("Pattern detected in high-priority tasks.", @response.body)
    assert_equal "deepseek-r1:14b", @user.reload.ai_summary_model
  end
end
