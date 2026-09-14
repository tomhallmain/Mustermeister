require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = User.new(
      name: "Test User",
      email: "unique_test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "should be valid" do
    assert @user.valid?
  end

  test "name should be present" do
    @user.name = ""
    assert_not @user.valid?
    assert_includes @user.errors[:name], "can't be blank"
  end

  test "email should be present" do
    @user.email = ""
    assert_not @user.valid?
    assert_includes @user.errors[:email], "can't be blank"
  end

  test "email should be unique" do
    duplicate_user = @user.dup
    @user.save
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "email should be valid format" do
    valid_emails = %w[user@example.com USER@foo.COM A_US-ER@foo.bar.org
                     first.last@foo.jp alice+bob@baz.cn]
    valid_emails.each do |email|
      @user.email = email
      assert @user.valid?, "#{email.inspect} should be valid"
    end
  end

  test "email should reject invalid formats" do
    invalid_emails = %w[user@example,com user_at_foo.org user.name@example.
                       foo@bar_baz.com foo@bar+baz.com]
    invalid_emails.each do |email|
      @user.email = email
      assert_not @user.valid?, "#{email.inspect} should be invalid"
    end
  end

  test "password should be present" do
    @user.password = @user.password_confirmation = " " * 6
    assert_not @user.valid?
    assert_includes @user.errors[:password], "can't be blank"
  end

  test "password should have a minimum length" do
    @user.password = @user.password_confirmation = "a" * 5
    assert_not @user.valid?
    assert_includes @user.errors[:password][0], "is too short"
  end

  test "password and password_confirmation should match" do
    @user.password = "password123"
    @user.password_confirmation = "different123"
    assert_not @user.valid?
    assert_includes @user.errors[:password_confirmation], "doesn't match Password"
  end

  test "should have many projects" do
    assert_respond_to @user, :projects
    assert_instance_of Project, @user.projects.build
  end

  test "should have many tasks" do
    assert_respond_to @user, :tasks
    assert_instance_of Task, @user.tasks.build
  end

  test "should have many comments" do
    assert_respond_to @user, :comments
    assert_instance_of Comment, @user.comments.build
  end

  test "task_insights_excluded_project_ids defaults to an empty array" do
    @user.save!
    assert_equal [], @user.reload.task_insights_excluded_project_ids
  end

  test "task_insights_excluded_project_ids can be persisted" do
    @user.save!
    @user.update!(task_insights_excluded_project_ids: [42, 7])
    assert_equal [42, 7], @user.reload.task_insights_excluded_project_ids
  end

  test "translate_target_language accepts a value from the allowed list" do
    @user.translate_target_language = "Japanese"
    assert @user.valid?
  end

  test "translate_target_language allows blank" do
    @user.translate_target_language = nil
    assert @user.valid?
  end

  test "translate_target_language rejects a value outside the allowed list" do
    @user.translate_target_language = "Klingon"
    assert_not @user.valid?
  end

  test "api_token_scope defaults to read and rejects anything outside the allowed list" do
    assert_equal "read", User.new.api_token_scope

    @user.api_token_scope = "read_write"
    assert @user.valid?

    @user.api_token_scope = "admin"
    assert_not @user.valid?
  end

  test "regenerating an API token stores only its digest and returns the raw token once" do
    user = users(:one)
    raw_token = user.regenerate_api_token!

    assert raw_token.present?
    assert_equal User.digest_api_token(raw_token), user.reload.api_token_digest
    assert_not_equal raw_token, user.api_token_digest
  end

  test "authenticate_api_token matches the raw token and nothing else" do
    user = users(:one)
    raw_token = user.regenerate_api_token!

    assert_equal user, User.authenticate_api_token(raw_token)
    assert_nil User.authenticate_api_token("#{raw_token}x")
    assert_nil User.authenticate_api_token(user.api_token_digest)
    assert_nil User.authenticate_api_token("")
    assert_nil User.authenticate_api_token(nil)
  end

  test "regenerating an API token invalidates the previous one" do
    user = users(:one)
    old_token = user.regenerate_api_token!
    new_token = user.regenerate_api_token!

    assert_nil User.authenticate_api_token(old_token)
    assert_equal user, User.authenticate_api_token(new_token)
  end
end
