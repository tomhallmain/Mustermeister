# Be sure to restart your server when you modify this file.

Rails.application.config.session_store :cookie_store,
  key: '_mustermeister_session',
  expire_after: 30.minutes,
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  domain: :all,
  tld_length: 2 