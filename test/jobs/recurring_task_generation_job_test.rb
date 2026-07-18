require "test_helper"

class RecurringTaskGenerationJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "perform generates tasks for every due schedule" do
    project = projects(:one)
    template = RecurringTaskTemplate.create!(
      title: "Water the plants",
      project: project,
      user: @user,
      base_unit: "month",
      interval: 1,
      start_date: 6.months.ago.to_date
    )

    assert_difference("Task.count", 1) do
      RecurringTaskGenerationJob.perform_now
    end

    assert_not_nil template.reload.last_generated_period_start
  end
end
