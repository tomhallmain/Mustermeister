class CspViolationReportsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    # Log CSP violations
    Rails.logger.warn("CSP Violation: #{request.body.read}")
    
    # Return 204 No Content
    head :no_content
  end
end 