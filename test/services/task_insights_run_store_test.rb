# frozen_string_literal: true

require "test_helper"

class TaskInsightsRunStoreTest < ActiveSupport::TestCase
  test "init read sync complete round trip" do
    run_id = SecureRandom.uuid
    TaskInsightsRunStore.init(run_id, user_id: 42)
    payload = TaskInsightsRunStore.read(run_id)
    assert_equal "running", payload["status"]
    assert_equal 42, payload["user_id"]

    TaskInsightsRunStore.sync_running(
      run_id,
      state_events: [{ state: "received_question", at: "t0" }],
      tool_calls: []
    )
    result = TaskInsightsChatService::Result.new(
      answer: "Done",
      tool_calls: [{ tool: "search_tasks", arguments: { "keyword" => "x" } }],
      state_events: [
        { state: "received_question", at: "t0" },
        { state: "final_answer_ready", at: "t1" }
      ]
    )
    TaskInsightsRunStore.complete!(run_id, result)
    final = TaskInsightsRunStore.read(run_id)
    assert_equal "complete", final["status"]
    assert_equal "Done", final["answer"]
    assert_equal 2, final["state_events"].size
  end
end
