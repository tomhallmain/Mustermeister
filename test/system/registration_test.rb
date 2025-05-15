require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  test "should register new user" do
    visit new_user_registration_path
    
    fill_in "Name", with: "New Test User"
    fill_in "Email", with: "newuser@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    
    assert_difference "User.count" do
      click_on "Sign up"
    end
    
    assert_text "Welcome! You have signed up successfully."
    assert_selector "h1", text: "Tasks" # Assuming this is the landing page after registration
  end
  
  test "should not register user with invalid data" do
    visit new_user_registration_path
    
    # Try to submit without filling in any fields
    assert_no_difference "User.count" do
      click_on "Sign up"
    end
    
    # Should show validation errors
    assert_text "can't be blank"
    
    # Try with mismatched passwords
    fill_in "Name", with: "New Test User"
    fill_in "Email", with: "newuser@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "different123"
    
    assert_no_difference "User.count" do
      click_on "Sign up"
    end
    
    assert_text "doesn't match Password"
  end
  
  test "should not register user with existing email" do
    # First create a user through the system
    visit new_user_registration_path
    fill_in "Name", with: "First User"
    fill_in "Email", with: "existing@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_on "Sign up"
    
    # Sign out
    click_on "Sign out"
    
    # Try to register with the same email
    visit new_user_registration_path
    fill_in "Name", with: "Second User"
    fill_in "Email", with: "existing@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    
    assert_no_difference "User.count" do
      click_on "Sign up"
    end
    
    assert_text "has already been taken"
  end
  
  test "should validate password length" do
    visit new_user_registration_path
    
    fill_in "Name", with: "New Test User"
    fill_in "Email", with: "newuser@example.com"
    fill_in "Password", with: "short"
    fill_in "Password confirmation", with: "short"
    
    assert_no_difference "User.count" do
      click_on "Sign up"
    end
    
    assert_text "is too short"
  end
end 