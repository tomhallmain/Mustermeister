# frozen_string_literal: true

require "json"

# Lets an LLM answer questions about a user's tasks via bounded read-only tool calls.
class TaskInsightsChatService
  MAX_TOOL_CALLS = 4
  # Upper bound for how many tasks a single list-style tool may return (default 1000).
  # Set TASK_INSIGHTS_MAX_LIST_ITEMS to a lower value in constrained environments.
  MAX_LIST_ITEMS_CAP = 1000
  MAX_LIST_ITEMS = [[ENV.fetch("TASK_INSIGHTS_MAX_LIST_ITEMS", MAX_LIST_ITEMS_CAP.to_s).to_i, 10].max, MAX_LIST_ITEMS_CAP].min

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
      args: { project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "high_priority_open_tasks",
      description: "List high-priority open tasks.",
      args: { project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "open_tasks_by_priorities",
      description: "List open tasks filtered by one or more priorities (e.g. medium and high).",
      args: {
        priorities: "required array of strings from leisure|low|medium|high",
        project_ids: "optional array of project ids",
        limit: "optional integer <= #{MAX_LIST_ITEMS}"
      }
    },
    {
      name: "recent_tasks",
      description: "List recently updated tasks.",
      args: { project_ids: "optional array of project ids", days: "optional integer", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "search_tasks",
      description: "Search task titles/descriptions via local substring matching.",
      args: { keyword: "required plain substring string (not a natural-language query)", project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    }
  ].freeze
  TOOL_NAMES = TOOL_DEFINITIONS.map { |tool| tool[:name] }.freeze

  SYSTEM_PROMPT = <<~PROMPT
    You are a task insights assistant.
    You may call tools to inspect task/project data before answering.
    RESPONSE CONTRACT (strict):
    - Return exactly one JSON object and nothing else (no markdown fences, no prose before/after JSON).
    - Tool call shape: {"type":"tool_call","tool":"tool_name","arguments":{...}}
    - Final answer shape: {"type":"final","answer":"plain text only as a JSON string"}
    - The "answer" value MUST be a JSON string (quoted text). Never put a JSON object or array as "answer".
      Put structured data only inside tool arguments or describe it in prose inside the string.
    - If no tool result has been provided yet, you MUST return a tool_call first.
    - After receiving one or more tool results, you may either call another tool or return final.
    - Never list available tools to the user; use them directly.
    - Tool calls are local function calls in this process, NOT a request to another agent/API.
    - Use ONLY the exact tool names listed in <TOOLS>. Do not invent names like task_manager/query_engine.
    - For text filtering, use search_tasks with a plain substring keyword (e.g. "backup"), not open-ended NL query text.
    - Do not call the same tool again with identical arguments if the result is already available in TOOL_RESULTS.
    - If the user asks about multiple priorities (e.g. medium and high), prefer open_tasks_by_priorities.
    Use at most one tool call per message.
  PROMPT

  def self.call(user:, question:, locale: I18n.locale, model_name: nil, excluded_project_ids: [], transcript_messages: [], progress: nil)
    new(
      user: user,
      locale: locale,
      model_name: model_name,
      excluded_project_ids: excluded_project_ids,
      transcript_messages: transcript_messages,
      progress: progress
    ).call(question)
  end

  def initialize(user:, locale:, model_name: nil, excluded_project_ids: [], transcript_messages: [], progress: nil)
    @user = user
    @locale = locale
    @progress = progress
    @excluded_project_ids = normalized_excluded_project_ids(excluded_project_ids)
    @transcript_messages = normalize_transcript_messages(transcript_messages)
    @llm = OllamaLlmService.new(model_name: model_name || default_model, state_key: "task_insights_#{user.id}")
    @tool_calls = []
    @state_events = []
    @tool_cache = {}
    @tool_result_history = []
  end

  def call(question)
    transcript = @transcript_messages.dup
    transcript << { role: "user", content: question.to_s }
    record_state(state: "received_question", at: Time.current.iso8601)

    MAX_TOOL_CALLS.times do
      record_state(state: "requesting_model_step", at: Time.current.iso8601)
      step = llm_step(transcript)
      if step["type"] == "final"
        answer = step["answer"].to_s.strip
        if answer.present?
          record_state(state: "final_answer_ready", at: Time.current.iso8601)
          return Result.new(answer: answer, tool_calls: @tool_calls, state_events: @state_events)
        end

        record_state(state: "final_answer_empty", at: Time.current.iso8601)
        break
      end
      break unless step["type"] == "tool_call"

      tool_step = @tool_calls.length + 1
      record_state(state: "executing_tool", tool: step["tool"], tool_step: tool_step, at: Time.current.iso8601)
      tool_key = tool_cache_key(step["tool"], step["arguments"] || {})
      reused = @tool_cache.key?(tool_key)
      tool_output = if reused
        @tool_cache[tool_key]
      else
        output = run_tool(step["tool"], step["arguments"] || {})
        @tool_cache[tool_key] = output
        output
      end
      result_count = tool_output_count(tool_output)
      tool_error = tool_output["error"] if tool_output.is_a?(Hash)
      record_state(state: "tool_result_reused", tool: step["tool"], tool_step: tool_step, at: Time.current.iso8601) if reused
      @tool_calls << {
        step: tool_step,
        tool: step["tool"],
        arguments: step["arguments"] || {},
        result_count: result_count,
        error: tool_error
      }
      unless reused
        @tool_result_history << {
          step: tool_step,
          tool: step["tool"],
          arguments: step["arguments"] || {},
          result: tool_output
        }
      end
      transcript << { role: "tool", content: { tool: step["tool"], result: summarize_tool_result(tool_output) }.to_json }
      record_state(
        state: "tool_result_received",
        tool: step["tool"],
        tool_step: tool_step,
        result_count: result_count,
        error: tool_error,
        at: Time.current.iso8601
      )
    end

    fallback = I18n.with_locale(@locale) { I18n.t("views.reports.analysis.ai_summary_error", default: "I couldn't complete the analysis. Please try rephrasing your question.") }
    record_state(state: "fallback_answer", at: Time.current.iso8601)
    Result.new(answer: fallback, tool_calls: @tool_calls, state_events: @state_events)
  end

  private

  def record_state(attrs)
    @state_events << attrs
    @progress&.sync(state_events: @state_events, tool_calls: @tool_calls)
  end

  def default_model
    ENV["OLLAMA_REPORT_MODEL"] || OllamaLlmService::DEFAULT_MODEL
  end

  def llm_step(transcript)
    prompt = build_prompt(transcript)
    log_debug("LLM prompt (main step)", prompt)
    response = @llm.generate_response(prompt, system_prompt: full_system_prompt)
    log_debug("LLM response (main step)", response.response.to_s)
    raw_text = response.response.to_s
    parsed = parse_llm_json(raw_text)
    if obvious_error_payload?(parsed)
      record_state(state: "model_error_payload", message: parsed["error"].to_s, at: Time.current.iso8601)
      return { "type" => "final", "answer" => "Model error: #{parsed['error']}" }
    end

    step = normalize_step(parsed, transcript: transcript)

    if step["type"] == "invalid"
      record_state(state: "model_response_invalid", at: Time.current.iso8601)
      repaired = attempt_json_repair(raw_text, transcript)
      step = normalize_step(repaired, transcript: transcript) if repaired
    end

    if step["type"] == "invalid"
      record_state(state: "model_response_unrecoverable", at: Time.current.iso8601)
    end

    step
  rescue StandardError
    record_state(state: "model_request_failed", at: Time.current.iso8601)
    { "type" => "invalid", "raw" => {} }
  end

  def build_prompt(transcript)
    has_tool_results = @tool_result_history.any?
    user_question = transcript.last&.dig(:content).to_s
    conversation_lines = transcript.filter_map do |m|
      role = m[:role].to_s.upcase
      next unless %w[USER ASSISTANT].include?(role)

      "#{role}: #{m[:content]}"
    end
    tool_results = build_tool_results_context
    cap = self.class::MAX_LIST_ITEMS
    <<~PROMPT
      <CONTEXT>
      task=Generate insights for the user's task list data.
      locale=#{@locale}
      has_tool_results=#{has_tool_results}
      list_limit_cap=#{cap}
      user_question=#{user_question}
      </CONTEXT>

      <TOOLS>
      Available tools:
      #{TOOL_DEFINITIONS.map { |t| "- #{t[:name]}: #{t[:description]} args=#{t[:args].to_json}" }.join("\n")}
      </TOOLS>

      <CONVERSATION>
      #{conversation_lines.join("\n")}
      </CONVERSATION>

      <TOOL_RESULTS>
      #{tool_results}
      </TOOL_RESULTS>

      <INSTRUCTION>
      Return one JSON object matching the response contract from system prompt.
      For list tools that accept "limit", use limit=#{cap} when you need broad coverage (or omit limit for the same default).
      Do not default to limit=10 unless you only need ten rows.
      For tool calls, ALWAYS return exactly:
      {"type":"tool_call","tool":"<exact listed tool name>","arguments":{...}}
      where "tool" is one of the names listed in <TOOLS>.
      </INSTRUCTION>
    PROMPT
  end

  def normalize_transcript_messages(messages)
    Array(messages).filter_map do |message|
      role = message[:role] || message["role"]
      content = message[:content] || message["content"]
      next unless %w[user assistant].include?(role.to_s)
      next if content.to_s.blank?

      { role: role.to_s, content: content.to_s }
    end
  end

  def parse_llm_json(text)
    cleaned = text.to_s.gsub("```", "").gsub("'''", "").strip
    cleaned = cleaned.delete_prefix("json").strip if cleaned.start_with?("json")
    json_candidate = cleaned
    unless json_candidate.start_with?("{") && json_candidate.end_with?("}")
      match = json_candidate.match(/\{.*\}/m)
      json_candidate = match[0] if match
    end
    data = JSON.parse(json_candidate)
    return data if data.is_a?(Hash)

    { "type" => "invalid", "raw" => { "parsed" => data } }
  rescue JSON::ParserError
    { "type" => "invalid", "raw" => { "text" => text.to_s } }
  end

  def build_tool_results_context
    return "none" if @tool_result_history.empty?

    summaries = @tool_result_history.map do |entry|
      {
        step: entry[:step],
        tool: entry[:tool],
        arguments: entry[:arguments],
        result_summary: summarize_tool_result(entry[:result])
      }
    end

    latest = @tool_result_history.last
    latest_full = {
      step: latest[:step],
      tool: latest[:tool],
      arguments: latest[:arguments],
      result: latest[:result]
    }

    <<~TEXT
      history_summaries=#{summaries.to_json}
      latest_result_full=#{latest_full.to_json}
    TEXT
  end

  def normalize_step(data, transcript:)
    return { "type" => "invalid", "raw" => data } unless data.is_a?(Hash)

    type = data["type"].to_s
    if type == "final"
      return { "type" => "invalid", "raw" => data } unless final_answer_json_ok?(data["answer"])
      return data
    end
    structured_final = normalize_structured_final_payload(data)
    return structured_final if structured_final
    return normalized_tool_call(data["tool"], data["arguments"]) if type == "tool_call"

    if data["tool_call"].is_a?(Hash)
      tc = data["tool_call"]
      return normalized_tool_call(tc["tool"] || tc["name"], tc["arguments"])
    end

    if data["tool_calls"].is_a?(Array) && data["tool_calls"].first.is_a?(Hash)
      call = data["tool_calls"].first
      tool_name = call["tool"] || call["tool_name"] || call["name"] || call["function"]
      tool_args = call["arguments"] || call["tool_args"] || call["args"]
      return normalized_tool_call(tool_name, tool_args)
    end

    if data["tool_name"].present?
      tool_args = data["arguments"] || data["parameters"] || data["tool_args"] || data["args"]
      return normalized_tool_call(data["tool_name"], tool_args)
    end

    tool = data["tool"] || data["name"]
    return normalized_tool_call(tool, data["arguments"]) if tool.present?

    { "type" => "invalid", "raw" => data }
  end

  def normalize_structured_final_payload(data)
    type = data["type"].to_s.downcase
    likely_final_type = %w[insights analysis summary result].include?(type)
    has_insight_keys = %w[trends_and_patterns recommendations batch_opportunities quick_wins].any? { |k| data.key?(k) }
    return nil unless likely_final_type || has_insight_keys

    content = data.dup
    content.delete("type")
    answer = JSON.pretty_generate(content)
    { "type" => "final", "answer" => answer }
  rescue StandardError
    nil
  end

  def final_answer_json_ok?(answer)
    answer.is_a?(String) || answer.is_a?(Numeric)
  end

  def normalized_tool_call(tool_name, arguments)
    tool = tool_name.to_s
    unless tool.present? && TOOL_NAMES.include?(tool)
      mapped = map_external_tool_call(tool, arguments)
      return mapped if mapped
      return { "type" => "invalid", "raw" => { "tool" => tool_name, "arguments" => arguments } }
    end

    args = arguments.is_a?(Hash) ? arguments : {}
    { "type" => "tool_call", "tool" => tool, "arguments" => args }
  end

  def map_external_tool_call(tool, arguments)
    args = arguments.is_a?(Hash) ? arguments : {}
    normalized = args.each_with_object({}) { |(k, v), h| h[k.to_s] = v }

    case tool
    when "get_tasks", "list_tasks", "fetch_tasks"
      # Bridge common external-agent style names to local tools.
      # - status completed/open -> status_breakdown for aggregate insight
      # - project/since_date filters -> search_tasks with project keyword fallback
      status = normalized["status"].to_s.downcase
      return { "type" => "tool_call", "tool" => "status_breakdown", "arguments" => {} } if status.present?

      keyword = normalized["keyword"].presence ||
        normalized["project"].presence ||
        normalized["query"].presence
      if keyword.present?
        limit = normalized["limit"] || self.class::MAX_LIST_ITEMS
        return {
          "type" => "tool_call",
          "tool" => "search_tasks",
          "arguments" => { "keyword" => keyword.to_s, "limit" => limit.to_i }
        }
      end

      { "type" => "tool_call", "tool" => "recent_tasks", "arguments" => { "limit" => self.class::MAX_LIST_ITEMS } }
    else
      nil
    end
  end

  def obvious_error_payload?(data)
    data.is_a?(Hash) && data["error"].present? && data["type"].blank? && data["tool"].blank? && data["tool_calls"].blank?
  end

  def tool_cache_key(tool_name, args)
    { tool: tool_name.to_s, arguments: deep_sort(args) }.to_json
  end

  def deep_sort(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }.sort.to_h
    when Array
      value.map { |v| deep_sort(v) }
    else
      value
    end
  end

  def full_system_prompt
    cap = self.class::MAX_LIST_ITEMS
    <<~PROMPT
      #{SYSTEM_PROMPT}

      LIST TOOLS: optional "limit" is clamped to #{cap}. Prefer limit=#{cap} when analyzing trends across many tasks, or omit "limit" for that same default. Avoid limit=10 unless you truly need only ten rows.
      TOOLS ARE LOCAL FUNCTIONS ONLY: do not use external-agent style schemas or invented tool names.
      SEARCH_TASKS NOTE: keyword is a plain local substring match over task title/description text.

      FINAL: "answer" must be a JSON string of human-readable prose, never a nested JSON object or array.
    PROMPT
  end

  def attempt_json_repair(bad_text, transcript)
    has_tool_results = transcript.any? { |m| m[:role] == "tool" }
    repair_prompt = <<~PROMPT
      Convert the assistant output below into EXACTLY one JSON object and nothing else.
      Valid shapes only:
      {"type":"tool_call","tool":"<tool_name>","arguments":{...}}
      {"type":"final","answer":"<plain text>"}

      Rules:
      - If has_tool_results is false, you MUST output tool_call (not final).
      - has_tool_results=#{has_tool_results}
      - Choose the best tool from the tool list in the main system prompt.
      - arguments must be a JSON object (use {} if none).
      - For final, "answer" must be a JSON string (quoted prose). Never use a JSON object or array as answer.
      - If outputting tool_call, use this exact shape only:
        {"type":"tool_call","tool":"<exact listed tool name>","arguments":{...}}
      - "tool" must be one of the exact listed tool names.

      BAD_OUTPUT:
      #{bad_text.to_s.truncate(8000)}
    PROMPT

    record_state(state: "attempting_json_repair", at: Time.current.iso8601)
    log_debug("LLM prompt (repair step)", repair_prompt)
    response = @llm.generate_response(repair_prompt, system_prompt: full_system_prompt)
    log_debug("LLM response (repair step)", response.response.to_s)
    parse_llm_json(response.response)
  rescue StandardError
    nil
  end

  def log_debug(label, payload)
    sanitized = payload.to_s.gsub("```", "'''")
    Rails.logger.debug("[TaskInsightsChatService] #{label}:\n#{sanitized}")
  end

  def run_tool(tool_name, args)
    case tool_name.to_s
    when "project_summary" then project_summary(args)
    when "status_breakdown" then status_breakdown(args)
    when "overdue_tasks" then overdue_tasks(args)
    when "high_priority_open_tasks" then high_priority_open_tasks(args)
    when "open_tasks_by_priorities" then open_tasks_by_priorities(args)
    when "recent_tasks" then recent_tasks(args)
    when "search_tasks" then search_tasks(args)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  def tool_output_count(output)
    return output.size if output.is_a?(Array)
    return output["items"].size if output.is_a?(Hash) && output["items"].is_a?(Array)
    return output[:items].size if output.is_a?(Hash) && output[:items].is_a?(Array)

    nil
  end

  def summarize_tool_result(output)
    if output.is_a?(Hash)
      summary = {}
      error = output[:error] || output["error"]
      returned_count = output[:returned_count] || output["returned_count"]
      total_matching_count = output[:total_matching_count] || output["total_matching_count"]
      limit = output[:limit] || output["limit"]
      summary[:error] = error if error.present?
      summary[:returned_count] = returned_count if returned_count.present?
      summary[:total_matching_count] = total_matching_count if total_matching_count.present?
      summary[:limit] = limit if limit.present?
      summary[:keys] = output.keys.map(&:to_s).sort if summary.empty?
      return summary
    end
    return { returned_count: output.size } if output.is_a?(Array)

    { value_class: output.class.name }
  end

  def scoped_tasks(project_ids = nil)
    scope = @user.tasks.not_archived.includes(:project, :status)
    scope = scope.where.not(project_id: @excluded_project_ids) if @excluded_project_ids.present?
    return scope if project_ids.blank?

    scope.where(project_id: normalized_project_ids(project_ids))
  end

  def normalized_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    allowed = @user.projects.where(id: ids).pluck(:id)
    @excluded_project_ids.present? ? allowed - @excluded_project_ids : allowed
  end

  def normalized_excluded_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    return [] if ids.empty?

    @user.projects.where(id: ids).pluck(:id).map(&:to_i)
  end

  def normalized_limit(limit)
    [[limit.to_i, 1].max, self.class::MAX_LIST_ITEMS].min
  end

  def format_task(task)
    data = {
      id: task.id,
      title: task.title,
      project: task.project&.title,
      status: task.status&.name,
      priority: task.priority,
      updated_date: task.updated_at&.to_date&.iso8601
    }
    due = task.due_date&.to_date&.iso8601
    data[:due_date] = due if due.present?
    data
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
    limit = normalized_limit(args["limit"] || self.class::MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false)
      .where("due_date < ?", Time.current)
      .order(due_date: :asc)
    list_result(scope, limit: limit)
  end

  def high_priority_open_tasks(args)
    limit = normalized_limit(args["limit"] || self.class::MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false, priority: "high")
      .order(updated_at: :asc)
    list_result(scope, limit: limit)
  end

  def open_tasks_by_priorities(args)
    allowed = %w[leisure low medium high]
    priorities = Array(args["priorities"]).map(&:to_s).uniq & allowed
    if priorities.blank?
      return {
        error: "priorities must include at least one of #{allowed.join(', ')}",
        items: [],
        returned_count: 0,
        total_matching_count: 0,
        limit: 0
      }
    end

    limit = normalized_limit(args["limit"] || self.class::MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false, priority: priorities)
      .order(updated_at: :asc)
    grouped_list_result(scope, limit: limit)
  end

  def recent_tasks(args)
    limit = normalized_limit(args["limit"] || self.class::MAX_LIST_ITEMS)
    days = [args["days"].to_i, 1].max
    scope = scoped_tasks(args["project_ids"])
      .where("tasks.updated_at >= ?", days.days.ago)
      .order(updated_at: :desc)
    list_result(scope, limit: limit)
  end

  def search_tasks(args)
    keyword = args["keyword"].to_s.strip
    if keyword.blank?
      return {
        error: "keyword is required",
        items: [],
        returned_count: 0,
        total_matching_count: 0,
        limit: 0
      }
    end

    limit = normalized_limit(args["limit"] || self.class::MAX_LIST_ITEMS)
    pattern = "%#{keyword.downcase}%"
    scope = scoped_tasks(args["project_ids"])
      .where("LOWER(tasks.title) LIKE :q OR LOWER(tasks.description) LIKE :q", q: pattern)
      .order(updated_at: :desc)
    list_result(scope, limit: limit)
  end

  def list_result(scope, limit:)
    total_matching_count = scope.except(:limit, :offset).count
    items = scope.limit(limit).map { |task| format_task(task) }
    {
      items: items,
      returned_count: items.size,
      total_matching_count: total_matching_count,
      limit: limit
    }
  end

  def grouped_list_result(scope, limit:)
    limited_items = scope.limit(limit).map { |task| format_task(task) }
    grouped = {}
    limited_items.each do |task|
      priority = task[:priority].presence || "unknown"
      status = task[:status].presence || "unknown"
      project = task[:project].presence || "unknown"
      grouped[priority] ||= { statuses: {} }
      grouped[priority][:statuses][status] ||= { projects: {} }
      grouped[priority][:statuses][status][:projects][project] ||= []
      grouped[priority][:statuses][status][:projects][project] << task.except(:priority, :status, :project)
    end

    {
      priorities: grouped,
      returned_count: limited_items.size,
      total_matching_count: scope.except(:limit, :offset).count,
      limit: limit
    }
  end
end
