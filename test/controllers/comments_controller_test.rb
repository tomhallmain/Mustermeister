require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @task = tasks(:one)
    sign_in_as(@user, skip_redirect: true)
    setup_paper_trail(@user)
  end

  def teardown
    teardown_paper_trail
  end

  test "comments on a task in one's own project" do
    assert_difference -> { @task.comments.count }, 1 do
      post task_comments_path(@task), params: { comment: { content: "Looks good to me" } }
    end

    assert_redirected_to task_path(@task)
  end

  test "cannot comment on a task in another user's project" do
    other_task = projects(:two).create_task!(title: "Someone else's task", user: users(:two))

    assert_no_difference -> { Comment.count } do
      post task_comments_path(other_task), params: { comment: { content: "Sneaking in" } }
    end

    assert_response :not_found
  end
end
