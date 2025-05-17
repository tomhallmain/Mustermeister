# Be sure to restart your server when you modify this file.

SecureHeaders::Configuration.default do |config|
  # Secure Headers configuration
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = %w(strict-origin-when-cross-origin)
  config.hsts = "max-age=31536000; includeSubDomains; preload"
  
#   # Set Permissions Policy using feature_policy
#   config.feature_policy = {
#     geolocation: [],
#     microphone: [],
#     camera: [],
#     payment: [],
#     usb: [],
#     fullscreen: [],
#     accelerometer: [],
#     autoplay: [],
#     encrypted_media: [],
#     midi: [],
#     sync_xhr: [],
#     magnetometer: [],
#     gyroscope: [],
#     speaker: [],
#     vibrate: [],
#     push: [],
#     interest_cohort: []
#   }

  # Generate session nonces for permitted importmap and inline scripts
#   config.csp_nonce_generator = ->(request) { request.session.id.to_s }
#   config.csp_nonce_directives = %w(script-src script-src-elem)

  # Content Security Policy
  config.csp = {
    preserve_schemes: true,
    disable_nonce_backwards_compatibility: true,
    
    default_src: %w('self'),
    base_uri: %w('self'),
    child_src: %w('self'),
    connect_src: %w('self'),
    font_src: %w('self' data:),
    form_action: %w('self'),
    frame_ancestors: %w('none'),
    img_src: %w('self' data:),
    manifest_src: %w('self'),
    media_src: %w('self'),
    object_src: %w('none'),
    script_src: %w('self' 'unsafe-inline' https://ga.jspm.io),
    script_src_elem: %w('self' 'unsafe-inline' https://ga.jspm.io),
    script_src_attr: %w('self' 'unsafe-inline'),
    style_src: %w('self' 'unsafe-inline'),
    style_src_elem: %w('self' 'unsafe-inline'),
    style_src_attr: %w('self' 'unsafe-inline'),
    worker_src: %w('self'),
    upgrade_insecure_requests: true,
    report_uri: %w(/csp-violation-report)
  }

  # Report violations without enforcing the policy in development
  if Rails.env.development?
    config.csp_report_only = config.csp.merge({
      report_uri: %w(/csp-violation-report)
    })
  end
end 