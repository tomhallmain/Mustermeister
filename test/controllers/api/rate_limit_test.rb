require "test_helper"

class Api::RateLimitTest < ActionDispatch::IntegrationTest
  # Mirrors the 'api/token/write' throttle in config/initializers/rack_attack.rb.
  WRITE_LIMIT = 60

  def setup
    @user = users(:one)
    @token = @user.regenerate_api_token!

    # rack_attack is switched off in the test environment, and the test cache
    # is a null store that would never accumulate a count, so both have to be
    # stood up explicitly here. A fresh store per test also keeps one test's
    # counters from deciding another's outcome under random ordering.
    #
    # Both are process-global, so both are captured and put back rather than
    # reset to an assumed value: the initializer leaves rack_attack enabled
    # when ENABLE_RACK_ATTACK is set, and hardcoding "off" here would switch
    # it off for every test that ran after this one.
    @original_enabled = Rack::Attack.enabled
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
  end

  def teardown
    Rack::Attack.enabled = @original_enabled
    Rack::Attack.cache.store = @original_store
  end

  test "the write throttle rejects a client that exceeds its budget" do
    WRITE_LIMIT.times do |i|
      post_write
      assert_not_equal 429, response.status, "request #{i + 1} should still be within budget"
    end

    post_write
    assert_response :too_many_requests
    assert_equal WRITE_LIMIT.to_s, response.headers['X-RateLimit-Limit']
    assert_equal 'Rate limit exceeded. Please try again later.', JSON.parse(response.body)['error']
  end

  test "read requests do not consume the write budget" do
    (WRITE_LIMIT + 1).times do
      get api_tool_path(tool_name: "status_breakdown"), headers: auth_headers(@token)
    end

    assert_not_equal 429, response.status
  end

  test "each token carries its own budget rather than sharing one per IP" do
    (WRITE_LIMIT + 1).times { post_write }
    assert_response :too_many_requests

    other_token = users(:two).regenerate_api_token!
    post_write(other_token)

    assert_not_equal 429, response.status
  end

  test "a scripted user agent is allowed on the API but still blocked elsewhere" do
    get api_tool_path(tool_name: "status_breakdown"),
        headers: auth_headers(@token).merge("User-Agent" => "curl/8.5.0")
    assert_response :success

    get root_path, headers: { "User-Agent" => "curl/8.5.0" }
    assert_response :forbidden
  end

  test "a scanner user agent stays blocked on the API too" do
    get api_tool_path(tool_name: "status_breakdown"),
        headers: auth_headers(@token).merge("User-Agent" => "sqlmap/1.7")

    assert_response :forbidden
  end

  private

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def post_write(token = @token)
    post api_tool_path(tool_name: "set_scheduled_at"), headers: auth_headers(token)
  end
end
