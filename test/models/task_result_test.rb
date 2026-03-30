require "test_helper"

class TaskResultTest < ActiveSupport::TestCase
  def setup
    @task = tasks(:one)
  end

  test "requires reason when result is incomplete" do
    result = TaskResult.new(task: @task, result: :incomplete, result_reason: nil)
    assert_not result.valid?
    assert_includes result.errors[:result_reason], "can't be blank"
  end

  test "does not allow reason when result is complete" do
    result = TaskResult.new(task: @task, result: :complete, result_reason: "Should not be set")
    assert_not result.valid?
    assert_includes result.errors[:result_reason], "must be blank"
  end
end
