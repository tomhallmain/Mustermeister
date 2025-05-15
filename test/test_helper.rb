require "simplecov"
SimpleCov.start

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
  def sign_in_as(user)
    post user_session_path, params: { 
      user: { 
        email: user.email, 
        password: 'password' 
      } 
    }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end
end

class ActionDispatch::IntegrationTest
  def sign_in_as(user, skip_redirect: false)
    if skip_redirect
      # Force JSON format to skip HTML/CSS rendering
      post user_session_path, 
        params: { 
          user: { 
            email: user.email, 
            password: 'password' 
          } 
        }.to_json, 
        headers: { 
          'Accept' => 'application/json', 
          'Content-Type' => 'application/json' 
        }
      assert_response :success
      # Directly set the authentication token or session (if using Devise)
      @controller.sign_in(user) if defined?(@controller)
    else
      post user_session_path, params: { 
        user: { 
          email: user.email, 
          password: 'password' 
        } 
      }
      assert_response :redirect
      follow_redirect!
      assert_response :success
    end
  end
end
