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

# Run JavaScript tests and shim results into the Minitest summary (runs after Ruby tests)
if ENV["SKIP_JS_TESTS"].blank?
  require "json"
  require "fileutils"

  # Capture verbose at load time; ARGV is consumed by Minitest before after_run runs
  JAVASCRIPT_TEST_VERBOSE = ARGV.any? { |a| a.to_s =~ /\A-v/ }

  Minitest.after_run do
    Dir.chdir(Rails.root) do
      FileUtils.mkdir_p("tmp")
      out = File::NULL
      err = File::NULL
      success = system("yarn", "test", "--", "--json", "--outputFile=tmp/jest-results.json", out: out, err: err)
      json_path = Rails.root.join("tmp/jest-results.json")

      if json_path.exist?
        data = JSON.parse(File.read(json_path))
        total = data["numTotalTests"] || 0
        failed = data["numFailedTests"] || 0
        passed = data["numPassedTests"] || 0
        # Jest --json uses "testResults" array (per file); each has "assertionResults" (per test)
        test_results = data["testResults"] || []

        # Individual test results when verbose
        if JAVASCRIPT_TEST_VERBOSE && test_results.any?
          js_green = "\e[32m"
          js_red   = "\e[31m"
          js_yellow = "\e[33m"
          js_reset = "\e[0m"
          puts ""
          test_results.each do |suite|
            name = suite["name"].to_s
            suite_name = File.basename(name, ".*").sub(/_test$/, "").gsub(/_/, " ").strip
            (suite["assertionResults"] || []).each do |assertion|
              title = assertion["title"].to_s
              status = assertion["status"].to_s
              status_char = case status
                when "passed"  then "."
                when "failed"  then "E"
                when "pending", "todo" then "S"
                else "?"
              end
              color = case status
                when "passed"  then js_green
                when "failed"  then js_red
                when "pending", "todo" then js_yellow
                else js_reset
              end
              puts "  #{suite_name}##{title} = #{color}#{status_char}#{js_reset}"
              if assertion["status"] != "passed" && assertion["failureMessages"]&.any?
                assertion["failureMessages"].each { |msg| msg.to_s.each_line { |line| puts "    #{line.rstrip}" } }
              end
            end
          end
        end

        # Summary (multiple lines, clearer for failures)
        puts "\nJavaScript tests:"
        if total.zero?
          puts "  (no tests)"
        elsif failed.zero?
          puts "  #{total} test#{'s' if total != 1}, #{passed} passed"
        else
          puts "  #{total} test#{'s' if total != 1}, #{passed} passed, #{failed} failed"
          failed_tests = test_results.flat_map do |suite|
            (suite["assertionResults"] || []).select { |a| a["status"] != "passed" }.map { |a| a["title"].to_s }
          end
          puts "  Failed: #{failed_tests.join(', ')}" if failed_tests.any?
        end
      end

      unless success
        puts "JavaScript tests failed!"
        exit!(1)
      end
    end
  end
end
