require "test_helper"

class ReportStatsServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "completion_ratio is weighted by priority, not a flat task count" do
    project = Project.create!(title: "Weighted Report Project", user: @user)
    project.create_task!(title: "High done", completed: true, priority: "high", user: @user)
    project.create_task!(title: "Leisure open", completed: false, priority: "leisure", user: @user)

    result = ReportStatsService.call(Project.where(id: project.id), project_ids: [project.id])
    breakdown = result.projects_breakdown.first

    # weight: high=4, leisure=1 -> 4 / (4 + 1) = 80%, not the unweighted 50%
    assert_equal 80.0, breakdown.completion_ratio
    # amount = completion_fraction * task_count^SIZE_EXPONENT * avg_priority_weight^PRIORITY_EXPONENT
    # task_count=2, avg_priority_weight=(4+1)/2=2.5
    expected_amount = (0.8 * (2.0**Project::WEIGHTED_PROGRESS_SIZE_EXPONENT) * (2.5**Project::WEIGHTED_PROGRESS_PRIORITY_EXPONENT)).round(1)
    assert_equal expected_amount, breakdown.weighted_completed_amount

    assert_equal 80.0, result.summary.completion_ratio
  end

  test "completion_ratio and weighted_completed_amount exclude archived tasks" do
    project = Project.create!(title: "Archived Exclusion Project", user: @user)
    project.create_task!(title: "Done", completed: true, priority: "medium", user: @user)
    stale = project.create_task!(title: "Archived but incomplete", completed: false, priority: "high", user: @user)
    stale.archive!(@user)

    result = ReportStatsService.call(Project.where(id: project.id), project_ids: [project.id])
    breakdown = result.projects_breakdown.first

    assert_equal 1, breakdown.total_tasks
    assert_equal 100.0, breakdown.completion_ratio
    # amount = completion_fraction * task_count^SIZE_EXPONENT * avg_priority_weight^PRIORITY_EXPONENT
    # task_count=1 (archived high task excluded), avg_priority_weight=3/1=3
    expected_amount = (1.0 * (1.0**Project::WEIGHTED_PROGRESS_SIZE_EXPONENT) * (3.0**Project::WEIGHTED_PROGRESS_PRIORITY_EXPONENT)).round(1)
    assert_equal expected_amount, breakdown.weighted_completed_amount
  end

  test "weighted_completed_amount rewards a larger, mostly-done project over a trivially small fully-done one" do
    small = Project.create!(title: "Small Done", user: @user)
    small.create_task!(title: "One task", completed: true, priority: "leisure", user: @user)

    big = Project.create!(title: "Big Mostly Done", user: @user)
    5.times { |i| big.create_task!(title: "Task #{i}", completed: true, priority: "high", user: @user) }
    big.create_task!(title: "Still open", completed: false, priority: "leisure", user: @user)

    result = ReportStatsService.call(Project.where(id: [small.id, big.id]))
    breakdown_by_title = result.projects_breakdown.index_by { |pb| pb.project.title }

    assert_equal 100.0, breakdown_by_title["Small Done"].completion_ratio
    assert breakdown_by_title["Big Mostly Done"].completion_ratio < 100.0
    assert breakdown_by_title["Big Mostly Done"].weighted_completed_amount > breakdown_by_title["Small Done"].weighted_completed_amount
  end

  test "weighted_completed_amount differentiates priority mix even at identical size and completion status" do
    leisure_project = Project.create!(title: "All Leisure", user: @user)
    9.times { |i| leisure_project.create_task!(title: "Done #{i}", completed: true, priority: "leisure", user: @user) }
    leisure_project.create_task!(title: "Open", completed: false, priority: "leisure", user: @user)

    medium_project = Project.create!(title: "All Medium", user: @user)
    9.times { |i| medium_project.create_task!(title: "Done #{i}", completed: true, priority: "medium", user: @user) }
    medium_project.create_task!(title: "Open", completed: false, priority: "medium", user: @user)

    result = ReportStatsService.call(Project.where(id: [leisure_project.id, medium_project.id]))
    breakdown_by_title = result.projects_breakdown.index_by { |pb| pb.project.title }
    leisure_breakdown = breakdown_by_title["All Leisure"]
    medium_breakdown = breakdown_by_title["All Medium"]

    # Same task count (10) and completion status (90%) - only priority mix differs.
    assert_equal leisure_breakdown.total_tasks, medium_breakdown.total_tasks
    assert_equal leisure_breakdown.completion_ratio, medium_breakdown.completion_ratio

    # medium (weight 3) vs leisure (weight 1) should differ by ~3^PRIORITY_EXPONENT,
    # not tie and not just the milder ~3^SIZE_EXPONENT gap the coupled formula gave before.
    expected_ratio = 3.0**Project::WEIGHTED_PROGRESS_PRIORITY_EXPONENT
    actual_ratio = medium_breakdown.weighted_completed_amount / leisure_breakdown.weighted_completed_amount
    assert_in_delta expected_ratio, actual_ratio, 0.05
  end

  test "completion_ratio is 0 for a project with no tasks" do
    project = Project.create!(title: "Empty Project", user: @user)

    result = ReportStatsService.call(Project.where(id: project.id), project_ids: [project.id])
    breakdown = result.projects_breakdown.first

    assert_equal 0, breakdown.completion_ratio
    assert_equal 0, breakdown.weighted_completed_amount
  end
end
