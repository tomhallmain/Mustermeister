# frozen_string_literal: true

class ReportLlmSummaryService
  SYSTEM_PROMPT = <<~PROMPT
    You are an assistant that summarizes project analytics for a task management app.
    Be concise, actionable, and specific.
    Output plain text only.
  PROMPT

  def self.call(result:, locale:, model_name: nil)
    new(result: result, locale: locale, model_name: model_name).call
  end

  def initialize(result:, locale:, model_name: nil)
    @result = result
    @locale = locale
    @model_name = model_name
  end

  def call
    llm = OllamaLlmService.new(model_name: @model_name || OllamaLlmService::DEFAULT_MODEL, state_key: "reports")
    response = llm.generate_response(prompt, system_prompt: SYSTEM_PROMPT)
    response.response
  end

  private

  def prompt
    summary = @result.summary
    projects = @result.projects_breakdown
    project_lines = projects.first(12).map do |pb|
      statuses = ReportStatsService.sorted_status_breakdown(pb.status_breakdown).map { |name, count| "#{name}: #{count}" }.join(", ")
      "- #{pb.project.title}: tasks=#{pb.total_tasks}, completed=#{pb.completed_count}, incomplete=#{pb.incomplete_count}, completion=#{pb.completion_ratio}%, status=[#{statuses}]"
    end.join("\n")

    <<~PROMPT
      Locale: #{@locale}
      Create a short executive report summary based on this data:

      Overall:
      - total_tasks: #{summary.total_tasks}
      - completed: #{summary.completed_count}
      - incomplete: #{summary.incomplete_count}
      - completion_ratio: #{summary.completion_ratio}%

      Projects:
      #{project_lines}

      Requirements:
      - 3 short sections: "Key findings", "Risks", "Recommended next actions"
      - Max 180 words
      - Refer to concrete metrics from the input
    PROMPT
  end
end
