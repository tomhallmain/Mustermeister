require "simplecov"
SimpleCov.start

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "capybara/rails"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
  def sign_in_as(user, format: :html)
    post user_session_path, params: { 
      user: { 
        email: user.email, 
        password: 'password' 
      } 
    }, as: format
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  def debug(message)
    puts message if @verbose
  end

  def setup_paper_trail(user = nil, ip: "127.0.0.1", user_agent: "Rails Testing")
    user ||= @user
    PaperTrail.request.whodunnit = user.id
    PaperTrail.request.controller_info = {
      ip: ip,
      user_agent: user_agent
    }
    
    debug "PaperTrail setup:"
    debug "whodunnit: #{PaperTrail.request.whodunnit}"
    debug "controller_info: #{PaperTrail.request.controller_info.inspect}"
  end

  def teardown_paper_trail
    PaperTrail.request.whodunnit = nil
    PaperTrail.request.controller_info = {}
  end
end

class ActionDispatch::IntegrationTest
  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL

  # Reset sessions between tests
  teardown do
    Capybara.reset_sessions!
  end

  def sign_in_as(user, skip_redirect: false, format: :html)
    if skip_redirect
      # Force JSON format to skip HTML/CSS rendering
      post user_session_path, 
        params: { 
          user: { 
            email: user.email, 
            password: 'password' 
          } 
        }, 
        as: :json
      assert_response :success
      # Directly set the authentication token or session (if using Devise)
      @controller.sign_in(user) if defined?(@controller)
    else
      # Ensure session is maintained for Capybara
      post user_session_path, params: { 
        user: { 
          email: user.email, 
          password: 'password' 
        } 
      }
      assert_response :redirect
      follow_redirect!
      assert_response :success
      
      # Copy the session to Capybara's rack_test driver
      if Capybara.current_driver == :rack_test
        Capybara.current_session.driver.browser.set_cookie(
          "rack.session",
          @request.session.to_hash.to_json
        )
      end
    end
  end

  def debug(message)
    puts message if @verbose
  end

  def setup_paper_trail(user = nil, ip: "127.0.0.1", user_agent: "Rails Testing")
    user ||= @user
    PaperTrail.request.whodunnit = user.id
    PaperTrail.request.controller_info = {
      ip: ip,
      user_agent: user_agent
    }
    
    debug "PaperTrail setup:"
    debug "whodunnit: #{PaperTrail.request.whodunnit}"
    debug "controller_info: #{PaperTrail.request.controller_info.inspect}"
  end

  def teardown_paper_trail
    PaperTrail.request.whodunnit = nil
    PaperTrail.request.controller_info = {}
  end
end

# Configure Capybara to use rack_test driver
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :rack_test
