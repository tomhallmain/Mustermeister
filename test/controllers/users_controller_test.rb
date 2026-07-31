require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    UsersController.class_eval do
      layout 'test'
    end

    @user = users(:one)
    sign_in_as(@user, skip_redirect: true)
  end

  def teardown
    UsersController.class_eval do
      layout 'application'
    end
  end

  test "profile page shows no token message when the user has none" do
    @user.update!(api_token: nil)

    get profile_path

    assert_response :success
    assert_select "code", count: 0
  end

  test "profile page shows the current token when one is set" do
    @user.update!(api_token: "existing-token-abc")

    get profile_path

    assert_response :success
    assert_select "code", text: "existing-token-abc"
  end

  test "regenerating the API token sets a new token and redirects to profile" do
    @user.update!(api_token: "old-token")

    post regenerate_api_token_path

    assert_redirected_to profile_path
    @user.reload
    assert_not_nil @user.api_token
    assert_not_equal "old-token", @user.api_token
  end

  test "regenerating the API token works when the user has no existing token" do
    @user.update!(api_token: nil)

    post regenerate_api_token_path

    assert_redirected_to profile_path
    assert_not_nil @user.reload.api_token
  end
end
