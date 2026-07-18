require "test_helper"

class RecurringTaskTemplatesControllerTest < ActionDispatch::IntegrationTest
  def setup
    RecurringTaskTemplatesController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    @other_user = users(:two)
    @project = projects(:one)
    sign_in_as(@user, skip_redirect: true)

    setup_paper_trail
  end

  def teardown
    RecurringTaskTemplatesController.class_eval do
      layout 'application'
    end

    teardown_paper_trail
  end

  def valid_params
    {
      recurring_task_template: {
        title: "Water the plants",
        project_id: @project.id,
        base_unit: "month",
        interval: 1,
        start_date: 1.month.ago.to_date,
        priority: "medium"
      }
    }
  end

  test "index only lists the current user's own schedules" do
    mine = RecurringTaskTemplate.create!(title: "Mine", project: @project, user: @user, base_unit: "month", interval: 1, start_date: 1.month.ago.to_date)
    other_project = projects(:two)
    RecurringTaskTemplate.create!(title: "Not Mine", project: other_project, user: @other_user, base_unit: "month", interval: 1, start_date: 1.month.ago.to_date)

    get recurring_task_templates_path
    assert_response :success
    assert_match mine.title, response.body
    assert_no_match(/Not Mine/, response.body)
  end

  test "creates a schedule owned by the current user" do
    assert_difference("RecurringTaskTemplate.count") do
      post recurring_task_templates_path, params: valid_params
    end

    template = RecurringTaskTemplate.order(:created_at).last
    assert_equal @user, template.user
    assert_redirected_to recurring_task_templates_path
  end

  test "does not create a schedule with a blank title" do
    params = valid_params
    params[:recurring_task_template][:title] = ""

    assert_no_difference("RecurringTaskTemplate.count") do
      post recurring_task_templates_path, params: params
    end
    assert_response :unprocessable_entity
  end

  test "updates the current user's own schedule" do
    template = RecurringTaskTemplate.create!(title: "Original", project: @project, user: @user, base_unit: "month", interval: 1, start_date: 1.month.ago.to_date)

    patch recurring_task_template_path(template), params: { recurring_task_template: { title: "Renamed" } }

    assert_redirected_to recurring_task_templates_path
    assert_equal "Renamed", template.reload.title
  end

  test "does not allow editing another user's schedule" do
    other_project = projects(:two)
    template = RecurringTaskTemplate.create!(title: "Not Mine", project: other_project, user: @other_user, base_unit: "month", interval: 1, start_date: 1.month.ago.to_date)

    patch recurring_task_template_path(template), params: { recurring_task_template: { title: "Hijacked" } }

    assert_redirected_to recurring_task_templates_path
    assert_equal "Not Mine", template.reload.title
  end

  test "toggle flips the active flag" do
    template = RecurringTaskTemplate.create!(title: "Mine", project: @project, user: @user, base_unit: "month", interval: 1, start_date: 1.month.ago.to_date)

    patch toggle_recurring_task_template_path(template)
    assert_not template.reload.active?

    patch toggle_recurring_task_template_path(template)
    assert template.reload.active?
  end

  test "destroying a schedule does not destroy its generated tasks" do
    template = RecurringTaskTemplate.create!(title: "Mine", project: @project, user: @user, base_unit: "month", interval: 1, start_date: 6.months.ago.to_date)
    template.generate_pending_tasks!
    task = Task.order(created_at: :desc).first

    assert_no_difference("Task.count") do
      delete recurring_task_template_path(template)
    end
    assert_nil task.reload.recurring_task_template_id
  end
end
