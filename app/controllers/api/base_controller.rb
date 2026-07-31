# Deliberately does not inherit from ApplicationController - that base class
# carries Devise's session-based authenticate_user!, a session-timeout check,
# and locale negotiation, none of which apply to a stateless, token-authed
# API client.
module Api
  class BaseController < ActionController::Base
    before_action :authenticate_via_token!

    private

    def authenticate_via_token!
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      @current_api_user = token.present? ? User.find_by(api_token: token) : nil

      render json: { error: "Unauthorized" }, status: :unauthorized unless @current_api_user
    end
  end
end
