# frozen_string_literal: true

require "test_helper"

class TaskInsightsRunJobTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "perform threads excluded_project_ids through TaskInsightsChatService so excluded task data never reaches the LLM" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Top Secret Task", user: @user)
    included_project = projects(:one)
    included_project.create_task!(title: "Visible Task", user: @user)

    captured_prompts = []
    responses = [
      OllamaLlmService::Result.new(response: '{"type":"tool_call","tool":"recent_tasks","arguments":{"limit":200,"days":3650}}'),
      OllamaLlmService::Result.new(response: '{"type":"final","answer":"Here is your summary."}')
    ]
    fake_llm = Class.new do
      def initialize(responses, capture)
        @responses = responses
        @capture = capture
      end

      def generate_response(prompt, system_prompt:)
        @capture.call(prompt)
        @responses.shift
      end
    end.new(responses, ->(prompt) { captured_prompts << prompt })

    run_id = SecureRandom.uuid
    TaskInsightsRunStore.init(run_id, user_id: @user.id)

    OllamaLlmService.stub :new, fake_llm do
      TaskInsightsRunJob.perform_now(
        run_id, @user.id, "What have I worked on recently?", "en", nil, [excluded_project.id], nil
      )
    end

    payload = TaskInsightsRunStore.read(run_id)
    assert_equal "complete", payload["status"]

    prompt_after_tool_call = captured_prompts.last
    assert_includes prompt_after_tool_call, "Visible Task"
    assert_not_includes prompt_after_tool_call, "Top Secret Task"
  end

  test "perform defaults to no exclusions when excluded_project_ids is omitted" do
    included_project = projects(:one)
    included_project.create_task!(title: "Some Task", user: @user)

    responses = [OllamaLlmService::Result.new(response: '{"type":"final","answer":"ok"}')]
    fake_llm = Class.new do
      def initialize(responses)
        @responses = responses
      end

      def generate_response(_prompt, system_prompt:)
        @responses.shift
      end
    end.new(responses)

    run_id = SecureRandom.uuid
    TaskInsightsRunStore.init(run_id, user_id: @user.id)

    OllamaLlmService.stub :new, fake_llm do
      TaskInsightsRunJob.perform_now(run_id, @user.id, "Hi", "en", nil)
    end

    payload = TaskInsightsRunStore.read(run_id)
    assert_equal "complete", payload["status"]
    assert_equal "ok", payload["answer"]
  end
end
