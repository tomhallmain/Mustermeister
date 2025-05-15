require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new registration page" do
    get new_user_registration_path
    assert_response :success
    assert_select "h2", "Create your account"
  end

  test "should create new user" do
    assert_difference "User.count" do
      post user_registration_path, params: {
        user: {
          name: "New Test User",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    
    assert_redirected_to root_path
    assert_equal "Welcome! You have signed up successfully.", flash[:notice]
  end

  test "should not create user with invalid data" do
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: {
          name: "",
          email: "invalid-email",
          password: "short",
          password_confirmation: "different"
        }
      }
    end
    
    assert_response :unprocessable_entity
    assert_select ".field_with_errors" # Devise uses this class for error fields
    assert_select "div", text: /can't be blank/i
  end

  test "should not create user with existing email" do
    # First create a user
    user = User.create!(
      name: "Existing User",
      email: "existing@example.com",
      password: "password123"
    )
    
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: {
          name: "New User",
          email: "existing@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    
    assert_response :unprocessable_entity
    assert_select ".field_with_errors"
    assert_select "div", text: /has already been taken/i
  end

  test "should require password confirmation" do
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: ""
        }
      }
    end
    
    assert_response :unprocessable_entity
    assert_select ".field_with_errors"
    assert_select "div", text: /doesn't match password/i
  end

  test "should validate password length" do
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: {
          name: "New User",
          email: "newuser@example.com",
          password: "short",
          password_confirmation: "short"
        }
      }
    end
    
    assert_response :unprocessable_entity
    assert_select ".field_with_errors"
    assert_select "div", text: /is too short/i
  end
end 