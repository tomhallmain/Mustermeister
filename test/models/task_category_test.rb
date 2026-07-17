require "test_helper"

class TaskCategoryTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "should be valid with a name" do
    category = TaskCategory.new(name: "Research")
    assert category.valid?
  end

  test "should require a name" do
    category = TaskCategory.new(name: nil)
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "default category has no owning user" do
    assert_nil task_categories(:feature).user_id
    assert task_categories(:feature).default?
  end

  test "custom category belongs to its creating user" do
    category = task_categories(:custom_for_user_one)
    assert_equal @user, category.user
    assert_not category.default?
  end

  test "name must be unique per user, case-insensitively" do
    duplicate = TaskCategory.new(name: "spike", user: @user)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "two different users can each have a category with the same name" do
    other_user = users(:two)
    category = TaskCategory.new(name: "Spike", user: other_user)
    assert category.valid?
  end

  test "a default category name is not blocked by a same-named custom category" do
    category = TaskCategory.new(name: task_categories(:feature).name, user: @user)
    assert category.valid?
  end

  test "normalizes name by stripping whitespace" do
    category = TaskCategory.create!(name: "  Spike Two  ", user: @user)
    assert_equal "Spike Two", category.name
  end

  test "default_category_names returns the expected list" do
    assert_equal ["Feature", "Fix", "Tech Debt", "Chore", "Documentation"], TaskCategory.default_category_names
  end

  test "ensure_default_categories! is idempotent and creates only missing defaults" do
    assert_no_difference('TaskCategory.default_categories.count') do
      TaskCategory.ensure_default_categories!
    end

    TaskCategory.default_categories.destroy_all
    assert_difference('TaskCategory.default_categories.count', TaskCategory.default_category_names.size) do
      TaskCategory.ensure_default_categories!
    end
  end

  test "default_categories and custom_categories scopes partition correctly" do
    assert_includes TaskCategory.default_categories, task_categories(:feature)
    assert_not_includes TaskCategory.default_categories, task_categories(:custom_for_user_one)

    assert_includes TaskCategory.custom_categories, task_categories(:custom_for_user_one)
    assert_not_includes TaskCategory.custom_categories, task_categories(:feature)
  end

  test "display_name translates default categories and passes through custom names" do
    assert_equal "Feature", task_categories(:feature).display_name
    assert_equal "Spike", task_categories(:custom_for_user_one).display_name
  end

  test "deleting a custom category nullifies its tasks' task_category_id instead of destroying them" do
    task = tasks(:one)
    task.update!(task_category: task_categories(:custom_for_user_one))

    assert_no_difference('Task.count') do
      task_categories(:custom_for_user_one).destroy
    end

    assert_nil task.reload.task_category_id
  end
end
