# frozen_string_literal: true

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

  test "create starts async run and status returns completed answer" do
    responses = [
      OllamaLlmService::Result.new(response: '{"type":"tool_call","tool":"status_breakdown","arguments":{}}'),
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"Pattern detected."}')
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

    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      OllamaLlmService.stub :new, fake_llm do
        excluded_project_id = projects(:one).id
        post task_insights_path,
          params: {
            question: "What are risky patterns?",
            ai_locale: "en",
            ai_model: "deepseek-r1:14b",
            excluded_project_ids: [excluded_project_id]
          },
          as: :json
      end
    end

    assert_response :accepted
    parsed = JSON.parse(response.body)
    run_id = parsed["run_id"]
    conversation_id = parsed["conversation_id"]
    assert run_id.present?
    assert conversation_id.present?
    conversation = @user.task_insights_conversations.find(conversation_id)
    assert_equal 2, conversation.task_insights_messages.count
    assert_equal "user", conversation.task_insights_messages.order(:created_at).first.role
    assert_equal "assistant", conversation.task_insights_messages.order(:created_at).last.role

    get task_insights_status_path(run_id: run_id), as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "complete", body["status"]
    assert_equal "Pattern detected.", body["answer"]
    assert body["state_events"].is_a?(Array)
    assert_operator body["state_events"].size, :>=, 2
    assert_equal "deepseek-r1:14b", @user.reload.ai_summary_model
    assert_equal [projects(:one).id], @user.task_insights_excluded_project_ids
  end

  test "index preselects persisted excluded projects" do
    @user.update!(task_insights_excluded_project_ids: [projects(:one).id])
    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      get task_insights_path
      assert_response :success
      assert_select "input.excluded-project-checkbox[value='#{projects(:one).id}'][checked]"
    end
  end

  test "create appends to existing conversation" do
    conversation = @user.task_insights_conversations.create!(title: "Existing chat", last_message_at: Time.current)
    conversation.task_insights_messages.create!(role: "user", content: "Earlier question")
    responses = [OllamaLlmService::Result.new(response: '{"type":"final","answer":"Next answer"}')]
    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        @responses.shift
      end
    end.new(responses)

    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      OllamaLlmService.stub :new, fake_llm do
        post task_insights_path, params: {
          question: "Follow-up",
          ai_locale: "en",
          ai_model: "deepseek-r1:14b",
          conversation_id: conversation.id
        }, as: :json
      end
    end

    assert_response :accepted
    assert_equal conversation.id, JSON.parse(response.body)["conversation_id"]
    assert_equal 3, conversation.reload.task_insights_messages.count
  end

  test "status returns not found for unknown run id" do
    OllamaLlmService.stub :available_models, ["deepseek-r1:14b"] do
      get task_insights_status_path(run_id: SecureRandom.uuid), as: :json
    end
    assert_response :not_found
  end
end
