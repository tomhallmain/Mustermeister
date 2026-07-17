require "test_helper"

class TaskCategoriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    TaskCategoriesController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    @other_user = users(:two)
    sign_in_as(@user, skip_redirect: true)

    setup_paper_trail
  end

  def teardown
    TaskCategoriesController.class_eval do
      layout 'application'
    end

    teardown_paper_trail
  end

  test "should get index and ensure defaults exist" do
    TaskCategory.default_categories.destroy_all

    get task_categories_path
    assert_response :success

    TaskCategory.default_category_names.each do |name|
      assert TaskCategory.default_categories.exists?(name: name)
    end
  end

  test "index only lists the current user's own custom categories" do
    other_custom = TaskCategory.create!(name: "Only Other User's", user: @other_user)

    get task_categories_path
    assert_response :success

    assert_match task_categories(:custom_for_user_one).name, response.body
    assert_no_match(/#{Regexp.escape(other_custom.name)}/, response.body)
  end

  test "should create a custom category owned by the current user" do
    assert_difference('TaskCategory.count') do
      post task_categories_path, params: { task_category: { name: "Spike Two" } }
    end

    category = TaskCategory.find_by(name: "Spike Two")
    assert_equal @user, category.user
    assert_redirected_to task_categories_path
  end

  test "should not create a category with a blank name" do
    assert_no_difference('TaskCategory.count') do
      post task_categories_path, params: { task_category: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "should update the current user's own custom category" do
    category = task_categories(:custom_for_user_one)

    patch task_category_path(category), params: { task_category: { name: "Renamed Spike" } }

    assert_redirected_to task_categories_path
    assert_equal "Renamed Spike", category.reload.name
  end

  test "should not allow editing another user's custom category" do
    other_custom = TaskCategory.create!(name: "Belongs To Other", user: @other_user)

    patch task_category_path(other_custom), params: { task_category: { name: "Hijacked" } }

    assert_redirected_to task_categories_path
    assert_equal "Belongs To Other", other_custom.reload.name
  end

  test "should not allow editing a default category" do
    default_category = task_categories(:feature)

    patch task_category_path(default_category), params: { task_category: { name: "Hijacked" } }

    assert_redirected_to task_categories_path
    assert_equal "Feature", default_category.reload.name
  end

  test "should destroy the current user's own custom category" do
    category = task_categories(:custom_for_user_one)

    assert_difference('TaskCategory.count', -1) do
      delete task_category_path(category)
    end
    assert_redirected_to task_categories_path
  end

  test "should not allow destroying a default category" do
    default_category = task_categories(:feature)

    assert_no_difference('TaskCategory.count') do
      delete task_category_path(default_category)
    end
    assert_redirected_to task_categories_path
  end

  test "should not allow destroying another user's custom category" do
    other_custom = TaskCategory.create!(name: "Belongs To Other", user: @other_user)

    assert_no_difference('TaskCategory.count') do
      delete task_category_path(other_custom)
    end
    assert_redirected_to task_categories_path
  end
end
