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
    @user.update!(api_token_digest: nil)

    get profile_path

    assert_response :success
    assert_select "code", count: 0
  end

  test "profile page never renders a stored token, only that one is set" do
    @user.regenerate_api_token!

    get profile_path

    assert_response :success
    assert_select "code", count: 0
    assert_match I18n.t('views.users.profile.api_token_set'), response.body
  end

  test "regenerating the API token shows the raw token once and stores only its digest" do
    @user.regenerate_api_token!
    old_digest = @user.reload.api_token_digest

    post regenerate_api_token_path

    assert_redirected_to profile_path
    raw_token = flash[:api_token]
    assert raw_token.present?, "expected the new token to be shown once via flash"

    @user.reload
    assert_not_equal old_digest, @user.api_token_digest
    assert_equal User.digest_api_token(raw_token), @user.api_token_digest
    assert_equal @user, User.authenticate_api_token(raw_token)
  end

  test "regenerating the API token works when the user has no existing token" do
    @user.update!(api_token_digest: nil)

    post regenerate_api_token_path

    assert_redirected_to profile_path
    assert_not_nil @user.reload.api_token_digest
  end

  test "a freshly generated token is read-only until the scope is changed" do
    post regenerate_api_token_path

    assert_equal "read", @user.reload.api_token_scope
  end

  test "the token scope can be switched to read_write and back" do
    post update_api_token_scope_path, params: { api_token_scope: "read_write" }

    assert_redirected_to profile_path
    assert_equal "read_write", @user.reload.api_token_scope

    post update_api_token_scope_path, params: { api_token_scope: "read" }

    assert_equal "read", @user.reload.api_token_scope
  end

  test "an unrecognized token scope is rejected and leaves the current one intact" do
    @user.update!(api_token_scope: "read")

    post update_api_token_scope_path, params: { api_token_scope: "admin" }

    assert_redirected_to profile_path
    assert_equal "read", @user.reload.api_token_scope
  end
end
