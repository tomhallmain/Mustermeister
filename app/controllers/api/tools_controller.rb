module Api
  class ToolsController < BaseController
    before_action :require_write_scope!, only: :create

    def show
      unless TaskToolsService::TOOL_NAMES.include?(params[:tool_name])
        render json: { error: "Unknown tool: #{params[:tool_name]}" }, status: :not_found
        return
      end

      tools = TaskToolsService.new(
        user: @current_api_user,
        excluded_project_ids: @current_api_user.task_insights_excluded_project_ids
      )
      render json: tools.run(params[:tool_name], tool_args)
    end

    def create
      unless TaskWriteToolsService::TOOL_NAMES.include?(params[:tool_name])
        render json: { error: "Unknown tool: #{params[:tool_name]}" }, status: :not_found
        return
      end

      tools = TaskWriteToolsService.new(
        user: @current_api_user,
        excluded_project_ids: @current_api_user.task_insights_excluded_project_ids
      )
      result = tools.run(params[:tool_name], write_tool_args)

      # Unlike the read tools, which answer 200 with an error body, a failed
      # write has to be a non-2xx: a client must never record a slot as
      # written when nothing changed.
      render json: result, status: result[:error].present? ? :unprocessable_entity : :ok
    end

    private

    def tool_args
      params.permit(:limit, :days, :keyword, :from, :to, priorities: [], project_ids: []).to_h
    end

    def write_tool_args
      params.permit(:task_id, :scheduled_at, :status_name).to_h
    end
  end
end
