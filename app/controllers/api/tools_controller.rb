module Api
  class ToolsController < BaseController
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

    private

    def tool_args
      params.permit(:limit, :days, :keyword, :from, :to, priorities: [], project_ids: []).to_h
    end
  end
end
