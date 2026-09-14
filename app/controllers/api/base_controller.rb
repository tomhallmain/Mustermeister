# Deliberately does not inherit from ApplicationController - that base class
# carries Devise's session-based authenticate_user!, a session-timeout check,
# and locale negotiation, none of which apply to a stateless, token-authed
# API client.
module Api
  class BaseController < ActionController::Base
    # Authentication here is a bearer token in a header, never an ambient
    # session cookie, so a cross-site page cannot make an authenticated
    # request on a user's behalf and there is nothing for a CSRF token to
    # protect. Without this, every write request would fail the forgery check.
    skip_forgery_protection

    before_action :authenticate_via_token!

    private

    def authenticate_via_token!
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      @current_api_user = User.authenticate_api_token(token)

      render json: { error: "Unauthorized" }, status: :unauthorized unless @current_api_user
    end

    # Write access is opt-in per user and off by default, so a token issued
    # while this API was read-only cannot write once write tools exist.
    def require_write_scope!
      return if @current_api_user.api_token_read_write?

      render json: { error: "This API token is read-only" }, status: :forbidden
    end
  end
end
