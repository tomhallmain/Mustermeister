class HealthController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  def show
    render json: { status: "ok" }, status: :ok
  end
end 