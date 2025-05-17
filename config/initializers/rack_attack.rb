class Rack::Attack
  # Store the number of requests per IP
  Rack::Attack.cache.store = Rails.cache

  # Store the IP address of the request so we can throttle by IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle login attempts by IP address
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post? && req.params['user'].is_a?(Hash)
      req.params['user']['email'].to_s.downcase.gsub(/\s+/, '')
    end
  end

  # Throttle password reset requests by IP address
  throttle('password_reset/ip', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/password' && req.post?
      req.ip
    end
  end

  # Throttle password reset requests by email
  throttle('password_reset/email', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/password' && req.post? && req.params['email'].present?
      req.params['email'].to_s.downcase.gsub(/\s+/, '')
    end
  end

  # Throttle account confirmation requests by IP address
  throttle('confirmation/ip', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/confirmation' && req.post?
      req.ip
    end
  end

  # Throttle account confirmation requests by email
  throttle('confirmation/email', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/confirmation' && req.post? && req.params['email'].present?
      req.params['email'].to_s.downcase.gsub(/\s+/, '')
    end
  end

  # Throttle account unlock requests by IP address
  throttle('unlock/ip', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/unlock' && req.post?
      req.ip
    end
  end

  # Throttle account unlock requests by email
  throttle('unlock/email', limit: 3, period: 1.hour) do |req|
    if req.path == '/users/unlock' && req.post? && req.params['email'].present?
      req.params['email'].to_s.downcase.gsub(/\s+/, '')
    end
  end

  # Throttle API requests by IP address
  throttle('api/ip', limit: 300, period: 5.minutes) do |req|
    if req.path.start_with?('/api/')
      req.ip
    end
  end

  # Throttle API requests by user ID
  throttle('api/user', limit: 300, period: 5.minutes) do |req|
    if req.path.start_with?('/api/') && req.env['warden']&.user
      req.env['warden'].user.id
    end
  end

  # Block suspicious requests
  blocklist('block suspicious requests') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 5, findtime: 1.minute, bantime: 1.hour) do
      req.path.include?('/wp-admin') || 
      req.path.include?('/wp-login') ||
      req.path.include?('/administrator') ||
      req.path.include?('/admin.php') ||
      req.path.include?('/.env') ||
      req.path.include?('/config/database.yml')
    end
  end

  # Block suspicious user agents
  blocklist("block suspicious user agents") do |req|
    req.user_agent && (
      req.user_agent.include?("sqlmap") ||
      req.user_agent.include?("nikto") ||
      req.user_agent.include?("nmap") ||
      req.user_agent.include?("wget") ||
      req.user_agent.include?("curl")
    )
  end

  # Custom throttling response
  self.throttled_response = lambda do |env|
    now = Time.now
    match_data = env['rack.attack.match_data']
    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + (match_data[:period] - now.to_i % match_data[:period])).to_s
    }

    [ 429, headers, [{ error: "Rate limit exceeded. Please try again later." }.to_json] ]
  end

  # Disable Rack Attack in development and test environments unless explicitly enabled
  if (Rails.env.development? || Rails.env.test?) && !ENV['ENABLE_RACK_ATTACK']
    Rack::Attack.enabled = false
  end

  # Log blocked events
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    req = payload[:request]
    if req.env['rack.attack.match_type'] == :blocklist
      Rails.logger.info "Blocked request: #{req.ip} to #{req.path}"
    end
  end
end 