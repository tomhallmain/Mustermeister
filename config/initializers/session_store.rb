# Be sure to restart your server when you modify this file.

# expire_after has to stay above ApplicationController::SESSION_IDLE_TIMEOUT,
# which catches an idle session itself and needs the cookie to outlive it.
Rails.application.config.session_store :cookie_store,
  key: '_mustermeister_session',
  expire_after: 1.hours,
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  domain: :all,
  tld_length: 2 