require "test_helper"

class Api::ToolsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @user.update!(api_token: "test-token-123")
    setup_paper_trail(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "returns 401 when no Authorization header is given" do
    get api_tool_path(tool_name: "overdue_tasks")
    assert_response :unauthorized
  end

  test "returns 401 for an invalid token" do
    get api_tool_path(tool_name: "overdue_tasks"), headers: { "Authorization" => "Bearer wrong-token" }
    assert_response :unauthorized
  end

  test "returns 404 for an unknown tool name" do
    get api_tool_path(tool_name: "not_a_real_tool"), headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :not_found
  end

  test "recent_tasks returns the token owner's real task data" do
    task = tasks(:one)

    get api_tool_path(tool_name: "recent_tasks", days: 3650, limit: 200),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success

    body = JSON.parse(response.body)
    item = body["items"].find { |t| t["id"] == task.id }
    assert item, "expected #{task.title.inspect} in the response"
    assert_equal task.title, item["title"]
    assert item.key?("description")
    assert item.key?("completed")
  end

  test "status_breakdown returns real per-status counts" do
    get api_tool_path(tool_name: "status_breakdown"),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success

    body = JSON.parse(response.body)
    assert body.is_a?(Hash)
    assert_equal @user.tasks.not_archived.count, body.values.sum
  end

  test "never returns another user's tasks" do
    other_users_task = projects(:two).tasks.create!(title: "Other User's Task", user: users(:two))

    get api_tool_path(tool_name: "recent_tasks", days: 3650, limit: 200),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success

    body = JSON.parse(response.body)
    titles = body["items"].map { |t| t["title"] }
    assert_not_includes titles, other_users_task.title
  end

  test "never returns tasks from a project excluded via task_insights_excluded_project_ids" do
    excluded_project = Project.create!(title: "Confidential Project", user: @user)
    excluded_project.create_task!(title: "Top Secret Task", user: @user)
    @user.update!(task_insights_excluded_project_ids: [excluded_project.id])

    get api_tool_path(tool_name: "recent_tasks", days: 3650, limit: 200, project_ids: [excluded_project.id]),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal [], body["items"]
  end

  test "every known tool is reachable and returns a real (non-stub) response" do
    tool_params = {
      "project_summary" => {},
      "status_breakdown" => {},
      "overdue_tasks" => { limit: 10 },
      "high_priority_open_tasks" => { limit: 10 },
      "open_tasks_by_priorities" => { priorities: %w[high medium], limit: 10 },
      "recent_tasks" => { days: 3650, limit: 10 },
      "search_tasks" => { keyword: "test", limit: 10 }
    }

    TaskToolsService::TOOL_NAMES.each do |tool_name|
      get api_tool_path(tool_name: tool_name, **tool_params.fetch(tool_name)),
          headers: { "Authorization" => "Bearer #{@user.api_token}" }
      assert_response :success, "expected #{tool_name} to succeed"

      body = JSON.parse(response.body)
      assert_not(body.is_a?(Hash) && body["stub"], "#{tool_name} should not be a stub response")
    end
  end

  test "limit is honored up to MAX_LIST_ITEMS and clamped above that" do
    get api_tool_path(tool_name: "recent_tasks", days: 3650, limit: 5),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success
    assert_equal 5, JSON.parse(response.body)["limit"]

    get api_tool_path(tool_name: "recent_tasks", days: 3650, limit: TaskToolsService::MAX_LIST_ITEMS + 500),
        headers: { "Authorization" => "Bearer #{@user.api_token}" }
    assert_response :success
    assert_equal TaskToolsService::MAX_LIST_ITEMS, JSON.parse(response.body)["limit"]
  end
end
