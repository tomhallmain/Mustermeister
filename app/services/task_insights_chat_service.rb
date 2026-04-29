# frozen_string_literal: true

require "json"

# Lets an LLM answer questions about a user's tasks via bounded read-only tool calls.
class TaskInsightsChatService
  MAX_TOOL_CALLS = 4
  MAX_ITEMS = 10

  Result = Struct.new(:answer, :tool_calls, :state_events, keyword_init: true)

  TOOL_DEFINITIONS = [
    {
      name: "project_summary",
      description: "Summarize projects and task totals.",
      args: { project_ids: "optional array of project ids" }
    },
    {
      name: "status_breakdown",
      description: "Get task counts by status.",
      args: { project_ids: "optional array of project ids" }
    },
    {
      name: "overdue_tasks",
      description: "List overdue open tasks.",
      args: { project_ids: "optional array of project ids", limit: "optional integer <= 10" }
    },
    {
      name: "high_priority_open_tasks",
      description: "List high-priority open tasks.",
      args: { project_ids: "optional array of project ids", limit: "optional integer <= 10" }
    },
    {
      name: "recent_tasks",
      description: "List recently updated tasks.",
      args: { project_ids: "optional array of project ids", days: "optional integer", limit: "optional integer <= 10" }
    },
    {
      name: "search_tasks",
      description: "Search task titles/descriptions.",
      args: { keyword: "required string", project_ids: "optional array of project ids", limit: "optional integer <= 10" }
    }
  ].freeze

  SYSTEM_PROMPT = <<~PROMPT
    You are a task insights assistant.
    You may call tools to inspect task/project data before answering.
    RESPONSE CONTRACT (strict):
    - Return exactly one JSON object and nothing else (no markdown fences, no prose before/after JSON).
    - Tool call shape: {"type":"tool_call","tool":"tool_name","arguments":{...}}
    - Final answer shape: {"type":"final","answer":"..."}
    - If no tool result has been provided yet, you MUST return a tool_call first.
    - After receiving one or more tool results, you may either call another tool or return final.
    - Never list available tools to the user; use them directly.
    Use at most one tool call per message.
  PROMPT

  def self.call(user:, question:, locale: I18n.locale, model_name: nil)
    new(user: user, locale: locale, model_name: model_name).call(question)
  end

  def initialize(user:, locale:, model_name: nil)
    @user = user
    @locale = locale
    @llm = OllamaLlmService.new(model_name: model_name || default_model, state_key: "task_insights_#{user.id}")
    @tool_calls = []
    @state_events = []
  end

  def call(question)
    transcript = [{ role: "user", content: question.to_s }]
    @state_events << { state: "received_question", at: Time.current.iso8601 }

    MAX_TOOL_CALLS.times do
      @state_events << { state: "requesting_model_step", at: Time.current.iso8601 }
      step = llm_step(transcript)
      if step["type"] == "final"
        @state_events << { state: "final_answer_ready", at: Time.current.iso8601 }
        return Result.new(answer: step["answer"].to_s, tool_calls: @tool_calls, state_events: @state_events)
      end
      break unless step["type"] == "tool_call"

      @state_events << { state: "executing_tool", tool: step["tool"], at: Time.current.iso8601 }
      tool_output = run_tool(step["tool"], step["arguments"] || {})
      @tool_calls << { tool: step["tool"], arguments: step["arguments"] || {} }
      transcript << { role: "tool", content: { tool: step["tool"], result: tool_output }.to_json }
      @state_events << { state: "tool_result_received", tool: step["tool"], at: Time.current.iso8601 }
    end

    fallback = I18n.with_locale(@locale) { I18n.t("views.reports.analysis.ai_summary_error", default: "I couldn't complete the analysis. Please try rephrasing your question.") }
    @state_events << { state: "fallback_answer", at: Time.current.iso8601 }
    Result.new(answer: fallback, tool_calls: @tool_calls, state_events: @state_events)
  end

  private

  def default_model
    ENV["OLLAMA_REPORT_MODEL"] || OllamaLlmService::DEFAULT_MODEL
  end

  def llm_step(transcript)
    prompt = build_prompt(transcript)
    response = @llm.generate_response(prompt, system_prompt: SYSTEM_PROMPT)
    parse_llm_json(response.response)
  rescue StandardError
    { "type" => "final", "answer" => "" }
  end

  def build_prompt(transcript)
    has_tool_results = transcript.any? { |m| m[:role] == "tool" }
    <<~PROMPT
      <CONTEXT>
      locale=#{@locale}
      has_tool_results=#{has_tool_results}
      </CONTEXT>

      <TOOLS>
      Available tools:
      #{TOOL_DEFINITIONS.map { |t| "- #{t[:name]}: #{t[:description]} args=#{t[:args].to_json}" }.join("\n")}
      </TOOLS>

      <CONVERSATION>
      #{transcript.map { |m| "#{m[:role].upcase}: #{m[:content]}" }.join("\n")}
      </CONVERSATION>

      <INSTRUCTION>
      Return one JSON object matching the response contract from system prompt.
      </INSTRUCTION>
    PROMPT
  end

  def parse_llm_json(text)
    cleaned = text.to_s.gsub("```", "").strip
    cleaned = cleaned.delete_prefix("json").strip if cleaned.start_with?("json")
    json_candidate = cleaned
    unless json_candidate.start_with?("{") && json_candidate.end_with?("}")
      match = json_candidate.match(/\{.*\}/m)
      json_candidate = match[0] if match
    end
    data = JSON.parse(json_candidate)
    return data if data.is_a?(Hash)

    { "type" => "final", "answer" => text.to_s }
  rescue JSON::ParserError
    { "type" => "final", "answer" => text.to_s }
  end

  def run_tool(tool_name, args)
    case tool_name.to_s
    when "project_summary" then project_summary(args)
    when "status_breakdown" then status_breakdown(args)
    when "overdue_tasks" then overdue_tasks(args)
    when "high_priority_open_tasks" then high_priority_open_tasks(args)
    when "recent_tasks" then recent_tasks(args)
    when "search_tasks" then search_tasks(args)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  def scoped_tasks(project_ids = nil)
    scope = @user.tasks.not_archived.includes(:project, :status)
    return scope if project_ids.blank?

    scope.where(project_id: normalized_project_ids(project_ids))
  end

  def normalized_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    @user.projects.where(id: ids).pluck(:id)
  end

  def normalized_limit(limit)
    [[limit.to_i, 1].max, MAX_ITEMS].min
  end

  def format_task(task)
    {
      id: task.id,
      title: task.title,
      project: task.project&.title,
      status: task.status&.name,
      priority: task.priority,
      due_date: task.due_date&.to_date&.iso8601,
      updated_at: task.updated_at&.iso8601
    }
  end

  def project_summary(args)
    tasks = scoped_tasks(args["project_ids"])
    grouped = tasks.group(:project_id).count
    projects = @user.projects.where(id: grouped.keys).index_by(&:id)
    grouped.map do |project_id, total|
      open = tasks.where(project_id: project_id, completed: false).count
      {
        project: projects[project_id]&.title,
        total_tasks: total,
        open_tasks: open,
        completion_ratio: total.positive? ? (((total - open).to_f / total) * 100).round(1) : 0.0
      }
    end.sort_by { |row| -row[:total_tasks] }
  end

  def status_breakdown(args)
    scoped_tasks(args["project_ids"]).joins(:status).group("statuses.name").count
  end

  def overdue_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_ITEMS)
    scoped_tasks(args["project_ids"])
      .where(completed: false)
      .where("due_date < ?", Time.current)
      .order(due_date: :asc)
      .limit(limit)
      .map { |task| format_task(task) }
  end

  def high_priority_open_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_ITEMS)
    scoped_tasks(args["project_ids"])
      .where(completed: false, priority: "high")
      .order(updated_at: :asc)
      .limit(limit)
      .map { |task| format_task(task) }
  end

  def recent_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_ITEMS)
    days = [args["days"].to_i, 1].max
    scoped_tasks(args["project_ids"])
      .where("tasks.updated_at >= ?", days.days.ago)
      .order(updated_at: :desc)
      .limit(limit)
      .map { |task| format_task(task) }
  end

  def search_tasks(args)
    keyword = args["keyword"].to_s.strip
    return [] if keyword.blank?

    limit = normalized_limit(args["limit"] || MAX_ITEMS)
    pattern = "%#{keyword.downcase}%"
    scoped_tasks(args["project_ids"])
      .where("LOWER(tasks.title) LIKE :q OR LOWER(tasks.description) LIKE :q", q: pattern)
      .order(updated_at: :desc)
      .limit(limit)
      .map { |task| format_task(task) }
  end
end
